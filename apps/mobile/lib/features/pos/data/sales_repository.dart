import 'dart:convert';

import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
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
    required SessionContext sessionContext,
    required SyncService syncService,
    Uuid? uuid,
  })  : _database = database,
        _sessionContext = sessionContext,
        _syncService = syncService,
        _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final SessionContext _sessionContext;
  final SyncService _syncService;
  final Uuid _uuid;

  Future<SaleSubmission> submitSale({
    required List<CartLine> lines,
    required PaymentMethod paymentMethod,
  }) async {
    if (lines.isEmpty) throw StateError('The cart is empty');
    final tenantId = _sessionContext.tenantId;
    final branchId = _sessionContext.branchId;
    if (tenantId == null || branchId == null) {
      throw StateError('A business and branch must be selected');
    }
    final clientOperationId = _uuid.v4();
    final totalMinor = lines.fold<int>(0, (total, line) => total + line.lineTotalMinor);
    final payload = <String, dynamic>{
      'client_operation_id': clientOperationId,
      'items': [
        for (final line in lines)
          {'product_id': line.product.id, 'quantity': line.quantity},
      ],
      'payments': [
        {
          'method': paymentMethod.apiValue,
          'amount': ScaledDecimal.fromMinor(totalMinor),
        },
      ],
    };
    final now = DateTime.now().toUtc();
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

    await _syncService.flushPendingSales();
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
