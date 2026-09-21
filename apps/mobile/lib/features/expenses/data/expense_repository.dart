import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/expenses/domain/expense_summary.dart';
import 'package:uuid/uuid.dart';

class ExpenseRepository {
  ExpenseRepository({
    required ApiClient apiClient,
    required AppDatabase database,
    required SessionContext sessionContext,
    required SyncService syncService,
    Uuid? uuid,
  })  : _apiClient = apiClient,
        _database = database,
        _sessionContext = sessionContext,
        _syncService = syncService,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final AppDatabase _database;
  final SessionContext _sessionContext;
  final SyncService _syncService;
  final Uuid _uuid;

  Future<List<ExpenseSummary>> listExpenses() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/expenses');
    return (response.data ?? const <dynamic>[]).map((value) {
      final json = value as Map<String, dynamic>;
      return ExpenseSummary(
        id: json['id'].toString(),
        expenseNumber: json['expense_number'].toString(),
        category: json['category'].toString(),
        description: json['description'].toString(),
        amountMinor: ScaledDecimal.toMinor(json['amount']),
        paymentMethod: json['payment_method'].toString(),
        expenseDate: DateTime.tryParse(json['expense_date']?.toString() ?? '') ?? DateTime.now(),
        receiptDocumentId: json['receipt_document_id']?.toString(),
      );
    }).toList(growable: false);
  }

  Future<bool> createExpense({
    required String category,
    required String description,
    required int amountMinor,
    required String paymentMethod,
    String? receiptDocumentId,
  }) async {
    final tenantId = _sessionContext.tenantId;
    final branchId = _sessionContext.branchId;
    if (tenantId == null || branchId == null) {
      throw StateError('A business and branch must be selected');
    }

    final clientOperationId = _uuid.v4();
    final localDocument = receiptDocumentId == null
        ? null
        : await _database.getPendingDocument(receiptDocumentId);
    final payload = <String, dynamic>{
      'client_operation_id': clientOperationId,
      'category': category,
      'description': description.trim(),
      'amount': ScaledDecimal.fromMinor(amountMinor),
      'payment_method': paymentMethod,
      'receipt_document_id': localDocument == null ? receiptDocumentId : null,
    };
    final now = DateTime.now().toUtc();
    await _database.queueExpense(
      PendingExpensesCompanion.insert(
        clientOperationId: clientOperationId,
        tenantId: tenantId,
        branchId: branchId,
        payloadJson: jsonEncode(payload),
        localDocumentId: Value(localDocument?.localDocumentId),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _syncService.flushPendingExpenses();
    final pending = await _database.getPendingExpense(clientOperationId);
    if (pending?.status == 'conflict') {
      throw StateError(pending?.lastError ?? 'Expense needs sync review.');
    }
    return pending != null;
  }
}
