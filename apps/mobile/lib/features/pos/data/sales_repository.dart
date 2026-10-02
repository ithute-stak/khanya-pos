import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/customers/data/customer_database.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/domain/sales_history.dart';
import 'package:uuid/uuid.dart';

enum SaleSubmissionStatus { synced, queued, conflict }

class SaleSubmission {
  const SaleSubmission({required this.clientOperationId, required this.status});
  final String clientOperationId;
  final SaleSubmissionStatus status;
}

class SalesRepository {
  SalesRepository({
    ApiClient? apiClient,
    required AppDatabase database,
    required CustomerDatabase customerDatabase,
    required SessionContext sessionContext,
    required SyncService syncService,
    Uuid? uuid,
  })  : _apiClient = apiClient,
        _database = database,
        _customerDatabase = customerDatabase,
        _sessionContext = sessionContext,
        _syncService = syncService,
        _uuid = uuid ?? const Uuid();

  final ApiClient? _apiClient;
  final AppDatabase _database;
  final CustomerDatabase _customerDatabase;
  final SessionContext _sessionContext;
  final SyncService _syncService;
  final Uuid _uuid;

  Future<SaleSubmission> submitSale({
    required List<CartLine> lines,
    required PaymentMethod paymentMethod,
    String? customerId,
    int? immediatePaymentMinor,
  }) async {
    if (lines.isEmpty) throw StateError('The cart is empty');
    final tenantId = _sessionContext.tenantId;
    final branchId = _sessionContext.branchId;
    if (tenantId == null || branchId == null) {
      throw StateError('A business and branch must be selected');
    }

    final clientOperationId = _uuid.v4();
    final totalMinor = lines.fold<int>(0, (total, line) => total + line.lineTotalMinor);
    final paidMinor = immediatePaymentMinor ?? totalMinor;
    if (paidMinor < 0 || paidMinor > totalMinor) {
      throw StateError('Immediate payment must be between zero and the sale total.');
    }
    final creditMinor = totalMinor - paidMinor;
    if (creditMinor > 0 && customerId == null) {
      throw StateError('A customer is required when any amount is sold on credit.');
    }

    var creditReserved = false;
    if (creditMinor > 0) {
      await _customerDatabase.reserveCredit(
        clientOperationId: clientOperationId,
        tenantId: tenantId,
        branchId: branchId,
        customerId: customerId!,
        creditMinor: creditMinor,
      );
      creditReserved = true;
    }

    final now = DateTime.now().toUtc();
    final paymentStatus = creditMinor == 0
        ? 'paid'
        : paidMinor > 0
            ? 'partial'
            : 'unpaid';
    final payload = <String, dynamic>{
      'client_operation_id': clientOperationId,
      'customer_id': customerId,
      '_local_total_minor': totalMinor,
      '_local_paid_minor': paidMinor,
      '_local_balance_due_minor': creditMinor,
      '_local_payment_status': paymentStatus,
      '_local_completed_at': now.toIso8601String(),
      'items': [
        for (final line in lines)
          {'product_id': line.product.id, 'quantity': line.quantity},
      ],
      'payments': [
        if (paidMinor > 0)
          {
            'method': paymentMethod.apiValue,
            'amount': ScaledDecimal.fromMinor(paidMinor),
          },
      ],
    };
    try {
      await _database.queueSaleAndApplyStock(
        sale: PendingSalesCompanion.insert(
          clientOperationId: clientOperationId,
          tenantId: tenantId,
          branchId: branchId,
          payloadJson: jsonEncode(payload),
          createdAt: now,
          updatedAt: now,
        ),
        tenantId: tenantId,
        branchId: branchId,
        stockChanges: [
          for (final line in lines)
            LocalSaleStockChange(productId: line.product.id, quantityMilli: line.quantity * 1000),
        ],
      );
    } catch (_) {
      if (creditReserved) {
        await _customerDatabase.releaseCreditReservation(clientOperationId);
      }
      rethrow;
    }

    // Use the complete dependency-ordered pipeline. Pending purchases must
    // reach the server before a sale that depends on their received stock,
    // and customer receipts must remain after their credit sale.
    await _syncService.flushAll();
    final pending = await _database.getPendingSale(clientOperationId);
    if (pending == null) {
      return SaleSubmission(clientOperationId: clientOperationId, status: SaleSubmissionStatus.synced);
    }
    return SaleSubmission(
      clientOperationId: clientOperationId,
      status: switch (pending.status) {
        'synced' => SaleSubmissionStatus.synced,
        'conflict' => SaleSubmissionStatus.conflict,
        _ => SaleSubmissionStatus.queued,
      },
    );
  }

  Future<List<SaleHistoryEntry>> history({String? search}) async {
    final tenantId = _sessionContext.tenantId;
    final branchId = _sessionContext.branchId;
    if (tenantId == null || branchId == null) {
      throw StateError('A business and branch must be selected');
    }

    final localRows = await _database.getSalesForHistory(
      tenantId: tenantId,
      branchId: branchId,
    );
    final local = localRows
        .map(_localHistoryEntry)
        .whereType<SaleHistoryEntry>()
        .where((sale) {
          final query = search?.trim().toLowerCase() ?? '';
          return query.isEmpty || sale.saleNumber.toLowerCase().contains(query);
        })
        .toList(growable: false);

    final remote = <SaleHistoryEntry>[];
    final apiClient = _apiClient;
    if (apiClient != null) {
      try {
        final response = await apiClient.dio.get<List<dynamic>>(
          '/pos/sales',
          queryParameters: {
            if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
            'limit': 200,
          },
        );
        remote.addAll(
          (response.data ?? const <dynamic>[])
              .map((value) =>
                  SaleHistoryEntry.fromJson(Map<String, dynamic>.from(value as Map))),
        );
      } on DioException {
        // Local sales remain visible while offline or while the server is unavailable.
      }
    }

    final byId = <String, SaleHistoryEntry>{
      for (final sale in remote) sale.id: sale,
    };
    for (final sale in local) {
      if (!byId.containsKey(sale.id)) byId[sale.id] = sale;
    }
    final merged = byId.values.toList(growable: false)
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return merged;
  }

  SaleHistoryEntry? _localHistoryEntry(PendingSale sale) {
    try {
      final payload = Map<String, dynamic>.from(jsonDecode(sale.payloadJson) as Map);
      final totalMinor = (payload['_local_total_minor'] as num?)?.toInt();
      final balanceDueMinor =
          (payload['_local_balance_due_minor'] as num?)?.toInt() ?? 0;
      if (totalMinor == null) return null;

      final serverId = payload['_server_sale_id']?.toString();
      final serverNumber = payload['_server_sale_number']?.toString();
      final completedAt = DateTime.tryParse(
            payload['_server_completed_at']?.toString() ??
                payload['_local_completed_at']?.toString() ??
                '',
          ) ??
          sale.createdAt;

      final syncStatus = switch (sale.status) {
        'synced' => 'Synced',
        'conflict' => 'Needs attention',
        'syncing' => 'Syncing',
        _ => 'Queued',
      };

      return SaleHistoryEntry(
        id: serverId?.isNotEmpty == true ? serverId! : sale.clientOperationId,
        saleNumber: serverNumber?.isNotEmpty == true
            ? serverNumber!
            : 'LOCAL-${sale.clientOperationId.substring(0, 8).toUpperCase()}',
        totalMinor: totalMinor,
        balanceDueMinor: balanceDueMinor,
        paymentStatus:
            payload['_local_payment_status']?.toString() ?? 'paid',
        completedAt: completedAt,
        returnedTotalMinor: 0,
        returnStatus: 'none',
        refundableTotalMinor: totalMinor,
        syncStatus: syncStatus,
        localOnly: serverId == null || serverId.isEmpty,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SaleDetail> detail(String saleId) async {
    final apiClient = _requireApiClient();
    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>('/pos/sales/$saleId');
      return SaleDetail.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (error) {
      throw StateError(_message(error, 'Unable to load the sale.'));
    }
  }

  Future<void> returnItems({
    required String saleId,
    required Map<String, int> quantitiesMilliByLine,
    required String reason,
    required String refundMethod,
    String? refundReference,
  }) async {
    final items = <Map<String, dynamic>>[];
    for (final entry in quantitiesMilliByLine.entries) {
      if (entry.value <= 0) continue;
      items.add({
        'sale_line_id': entry.key,
        'quantity': ScaledDecimal.fromMilli(entry.value),
      });
    }
    if (items.isEmpty) throw StateError('Choose at least one item to return.');
    await _submitReturn(
      saleId: saleId,
      data: {
        'client_operation_id': _uuid.v4(),
        'kind': 'return',
        'items': items,
        'reason': reason.trim(),
        'refund_method': refundMethod,
        'refund_reference': _nullableText(refundReference),
      },
    );
  }

  Future<void> voidSale({
    required String saleId,
    required String reason,
    required String refundMethod,
    String? refundReference,
  }) {
    return _submitReturn(
      saleId: saleId,
      data: {
        'client_operation_id': _uuid.v4(),
        'kind': 'void',
        'items': const <Map<String, dynamic>>[],
        'reason': reason.trim(),
        'refund_method': refundMethod,
        'refund_reference': _nullableText(refundReference),
      },
    );
  }

  Future<void> _submitReturn({
    required String saleId,
    required Map<String, dynamic> data,
  }) async {
    final apiClient = _requireApiClient();
    try {
      await apiClient.dio.post<Map<String, dynamic>>(
        '/pos/sales/$saleId/returns',
        data: data,
      );
    } on DioException catch (error) {
      throw StateError(_message(error, 'Unable to process the return.'));
    }
  }

  ApiClient _requireApiClient() {
    final apiClient = _apiClient;
    if (apiClient == null) {
      throw StateError('Online sales history is unavailable in this repository configuration.');
    }
    return apiClient;
  }

  String _message(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    return fallback;
  }

  String? _nullableText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
