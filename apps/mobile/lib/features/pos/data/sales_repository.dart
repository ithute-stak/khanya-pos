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

    final payload = <String, dynamic>{
      'client_operation_id': clientOperationId,
      'customer_id': customerId,
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
    final now = DateTime.now().toUtc();

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
      status: pending.status == 'conflict' ? SaleSubmissionStatus.conflict : SaleSubmissionStatus.queued,
    );
  }

  Future<List<SaleHistoryEntry>> history({String? search}) async {
    final apiClient = _requireApiClient();
    try {
      final response = await apiClient.dio.get<List<dynamic>>(
        '/pos/sales',
        queryParameters: {
          if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
          'limit': 200,
        },
      );
      return (response.data ?? const <dynamic>[])
          .map((value) => SaleHistoryEntry.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList(growable: false);
    } on DioException catch (error) {
      throw StateError(_message(error, 'Unable to load sales history.'));
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
