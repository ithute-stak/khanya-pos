import 'dart:convert';

import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/customers/data/customer_database.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:uuid/uuid.dart';

enum SaleSubmissionStatus { synced, queued, conflict }

class SaleSubmission {
  const SaleSubmission({required this.clientOperationId, required this.status});
  final String clientOperationId;
  final SaleSubmissionStatus status;
}

class SalesRepository {
  SalesRepository({
    required AppDatabase database,
    required CustomerDatabase customerDatabase,
    required SessionContext sessionContext,
    required SyncService syncService,
    Uuid? uuid,
  })  : _database = database,
        _customerDatabase = customerDatabase,
        _sessionContext = sessionContext,
        _syncService = syncService,
        _uuid = uuid ?? const Uuid();

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
}
