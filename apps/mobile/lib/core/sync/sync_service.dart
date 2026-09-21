import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/features/customers/data/customer_database.dart';

class SyncRunResult {
  const SyncRunResult({
    required this.attempted,
    required this.synced,
    required this.conflicts,
    required this.networkUnavailable,
  });

  const SyncRunResult.empty()
      : attempted = 0,
        synced = 0,
        conflicts = 0,
        networkUnavailable = false;

  final int attempted;
  final int synced;
  final int conflicts;
  final bool networkUnavailable;

  SyncRunResult merge(SyncRunResult other) => SyncRunResult(
        attempted: attempted + other.attempted,
        synced: synced + other.synced,
        conflicts: conflicts + other.conflicts,
        networkUnavailable: networkUnavailable || other.networkUnavailable,
      );
}

class SyncService {
  SyncService({
    required ApiClient apiClient,
    required AppDatabase database,
    required CustomerDatabase customerDatabase,
  })  : _apiClient = apiClient,
        _database = database,
        _customerDatabase = customerDatabase;

  final ApiClient _apiClient;
  final AppDatabase _database;
  final CustomerDatabase _customerDatabase;

  Future<SyncRunResult> flushAll() async {
    var result = const SyncRunResult.empty();

    final documents = await flushPendingDocuments();
    result = result.merge(documents);
    if (documents.networkUnavailable) return result;

    final purchases = await _flushPendingPurchases(uploadDocumentsFirst: false);
    result = result.merge(purchases);
    if (purchases.networkUnavailable) return result;

    final sales = await flushPendingSales();
    result = result.merge(sales);
    if (sales.networkUnavailable) return result;

    final customerPayments = await flushPendingCustomerPayments();
    result = result.merge(customerPayments);
    if (customerPayments.networkUnavailable) return result;

    final expenses = await _flushPendingExpenses(uploadDocumentsFirst: false);
    return result.merge(expenses);
  }

  Future<SyncRunResult> flushPendingDocuments() async {
    final pending = await _database.getSyncablePendingDocuments();
    var attempted = 0;
    var synced = 0;
    var conflicts = 0;
    var networkUnavailable = false;

    for (final document in pending) {
      attempted += 1;
      await _database.markPendingDocument(
        localDocumentId: document.localDocumentId,
        status: 'uploading',
        incrementAttempts: true,
      );
      try {
        final file = File(document.localPath);
        if (!await file.exists()) {
          await _database.markPendingDocument(
            localDocumentId: document.localDocumentId,
            status: 'conflict',
            lastError: 'The saved receipt file is missing from this device.',
          );
          conflicts += 1;
          continue;
        }
        final endpoint = document.documentPurpose == 'expense'
            ? '/documents/expense-receipts'
            : '/documents/purchase-receipts';
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            document.localPath,
            filename: document.filename,
            contentType: DioMediaType.parse(document.contentType),
          ),
        });
        final response = await _apiClient.dio.post<Map<String, dynamic>>(
          endpoint,
          data: form,
          options: Options(contentType: 'multipart/form-data'),
        );
        final remoteId = response.data?['id']?.toString();
        if (remoteId == null || remoteId.isEmpty) {
          throw StateError('Receipt upload completed without a document id.');
        }
        await _database.markPendingDocument(
          localDocumentId: document.localDocumentId,
          status: 'uploaded',
          remoteDocumentId: remoteId,
        );
        synced += 1;
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        final detail = _errorDetail(error);
        if (_isPermanentClientError(statusCode)) {
          await _database.markPendingDocument(
            localDocumentId: document.localDocumentId,
            status: 'conflict',
            lastError: detail,
          );
          conflicts += 1;
          continue;
        }
        await _database.markPendingDocument(
          localDocumentId: document.localDocumentId,
          status: 'pending',
          lastError: detail,
        );
        if (error.response == null) networkUnavailable = true;
        break;
      } catch (error) {
        await _database.markPendingDocument(
          localDocumentId: document.localDocumentId,
          status: 'conflict',
          lastError: error.toString(),
        );
        conflicts += 1;
      }
    }

    return SyncRunResult(
      attempted: attempted,
      synced: synced,
      conflicts: conflicts,
      networkUnavailable: networkUnavailable,
    );
  }

  Future<SyncRunResult> flushPendingPurchases() {
    return _flushPendingPurchases(uploadDocumentsFirst: true);
  }

  Future<SyncRunResult> _flushPendingPurchases({required bool uploadDocumentsFirst}) async {
    var result = const SyncRunResult.empty();
    if (uploadDocumentsFirst) {
      final documents = await flushPendingDocuments();
      result = result.merge(documents);
      if (documents.networkUnavailable) return result;
    }

    final pending = await _database.getSyncablePendingPurchases();
    var attempted = 0;
    var synced = 0;
    var conflicts = 0;
    var networkUnavailable = false;

    for (final purchase in pending) {
      attempted += 1;
      await _database.markPendingPurchase(
        clientOperationId: purchase.clientOperationId,
        status: 'syncing',
        incrementAttempts: true,
      );
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(purchase.payloadJson) as Map);
        if (purchase.localDocumentId != null) {
          final document = await _database.getPendingDocument(purchase.localDocumentId!);
          if (document == null) {
            await _database.markPendingPurchase(
              clientOperationId: purchase.clientOperationId,
              status: 'conflict',
              lastError: 'The linked receipt record is missing.',
            );
            conflicts += 1;
            continue;
          }
          if (document.status == 'conflict') {
            await _database.markPendingPurchase(
              clientOperationId: purchase.clientOperationId,
              status: 'conflict',
              lastError: document.lastError ?? 'The linked receipt could not be uploaded.',
            );
            conflicts += 1;
            continue;
          }
          if (document.remoteDocumentId == null) {
            await _database.markPendingPurchase(
              clientOperationId: purchase.clientOperationId,
              status: 'pending',
              lastError: 'Waiting for receipt upload.',
            );
            continue;
          }
          payload['receipt_document_id'] = document.remoteDocumentId;
        }

        await _apiClient.dio.post<Map<String, dynamic>>('/purchases/receive', data: payload);
        final localDocumentId = purchase.localDocumentId;
        await _database.deletePendingPurchase(purchase.clientOperationId);
        await _cleanupDocument(localDocumentId);
        synced += 1;
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        final detail = _errorDetail(error);
        if (_isPermanentClientError(statusCode)) {
          await _database.markPendingPurchase(
            clientOperationId: purchase.clientOperationId,
            status: 'conflict',
            lastError: detail,
          );
          conflicts += 1;
          continue;
        }
        await _database.markPendingPurchase(
          clientOperationId: purchase.clientOperationId,
          status: 'pending',
          lastError: detail,
        );
        if (error.response == null) networkUnavailable = true;
        break;
      }
    }

    return result.merge(
      SyncRunResult(
        attempted: attempted,
        synced: synced,
        conflicts: conflicts,
        networkUnavailable: networkUnavailable,
      ),
    );
  }

  Future<SyncRunResult> flushPendingSales() async {
    final pending = await _database.getSyncablePendingSales();
    var attempted = 0;
    var synced = 0;
    var conflicts = 0;
    var networkUnavailable = false;

    for (final sale in pending) {
      attempted += 1;
      await _database.markPendingSale(
        clientOperationId: sale.clientOperationId,
        status: 'syncing',
        incrementAttempts: true,
      );
      try {
        await _apiClient.dio.post<Map<String, dynamic>>(
          '/pos/sales/complete',
          data: jsonDecode(sale.payloadJson),
        );
        await _customerDatabase.finalizeCreditReservation(sale.clientOperationId);
        await _database.deletePendingSale(sale.clientOperationId);
        synced += 1;
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        final detail = _errorDetail(error);
        if (_isPermanentClientError(statusCode)) {
          await _database.markPendingSale(
            clientOperationId: sale.clientOperationId,
            status: 'conflict',
            lastError: detail,
          );
          await _customerDatabase.releaseCreditReservation(sale.clientOperationId);
          conflicts += 1;
          continue;
        }
        await _database.markPendingSale(
          clientOperationId: sale.clientOperationId,
          status: 'pending',
          lastError: detail,
        );
        if (error.response == null) networkUnavailable = true;
        break;
      }
    }

    return SyncRunResult(
      attempted: attempted,
      synced: synced,
      conflicts: conflicts,
      networkUnavailable: networkUnavailable,
    );
  }

  Future<SyncRunResult> flushPendingCustomerPayments() async {
    final pending = await _customerDatabase.getSyncablePendingPayments();
    var attempted = 0;
    var synced = 0;
    var conflicts = 0;
    var networkUnavailable = false;

    for (final payment in pending) {
      attempted += 1;
      await _customerDatabase.markPendingPayment(
        clientOperationId: payment.clientOperationId,
        status: 'syncing',
        incrementAttempts: true,
      );
      try {
        await _apiClient.dio.post<Map<String, dynamic>>(
          '/customers/${payment.customerId}/payments',
          data: jsonDecode(payment.payloadJson),
        );
        await _customerDatabase.deletePendingPayment(payment.clientOperationId);
        synced += 1;
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        final detail = _errorDetail(error);
        if (_isPermanentClientError(statusCode)) {
          await _customerDatabase.markPendingPayment(
            clientOperationId: payment.clientOperationId,
            status: 'conflict',
            lastError: detail,
          );
          conflicts += 1;
          continue;
        }
        await _customerDatabase.markPendingPayment(
          clientOperationId: payment.clientOperationId,
          status: 'pending',
          lastError: detail,
        );
        if (error.response == null) networkUnavailable = true;
        break;
      }
    }

    return SyncRunResult(
      attempted: attempted,
      synced: synced,
      conflicts: conflicts,
      networkUnavailable: networkUnavailable,
    );
  }

  Future<SyncRunResult> flushPendingExpenses() {
    return _flushPendingExpenses(uploadDocumentsFirst: true);
  }

  Future<SyncRunResult> _flushPendingExpenses({required bool uploadDocumentsFirst}) async {
    var result = const SyncRunResult.empty();
    if (uploadDocumentsFirst) {
      final documents = await flushPendingDocuments();
      result = result.merge(documents);
      if (documents.networkUnavailable) return result;
    }

    final pending = await _database.getSyncablePendingExpenses();
    var attempted = 0;
    var synced = 0;
    var conflicts = 0;
    var networkUnavailable = false;

    for (final expense in pending) {
      attempted += 1;
      await _database.markPendingExpense(
        clientOperationId: expense.clientOperationId,
        status: 'syncing',
        incrementAttempts: true,
      );
      try {
        final payload = Map<String, dynamic>.from(jsonDecode(expense.payloadJson) as Map);
        if (expense.localDocumentId != null) {
          final document = await _database.getPendingDocument(expense.localDocumentId!);
          if (document == null) {
            await _database.markPendingExpense(
              clientOperationId: expense.clientOperationId,
              status: 'conflict',
              lastError: 'The linked receipt record is missing.',
            );
            conflicts += 1;
            continue;
          }
          if (document.status == 'conflict') {
            await _database.markPendingExpense(
              clientOperationId: expense.clientOperationId,
              status: 'conflict',
              lastError: document.lastError ?? 'The linked receipt could not be uploaded.',
            );
            conflicts += 1;
            continue;
          }
          if (document.remoteDocumentId == null) {
            await _database.markPendingExpense(
              clientOperationId: expense.clientOperationId,
              status: 'pending',
              lastError: 'Waiting for receipt upload.',
            );
            continue;
          }
          payload['receipt_document_id'] = document.remoteDocumentId;
        }

        await _apiClient.dio.post<Map<String, dynamic>>('/expenses', data: payload);
        final localDocumentId = expense.localDocumentId;
        await _database.deletePendingExpense(expense.clientOperationId);
        await _cleanupDocument(localDocumentId);
        synced += 1;
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        final detail = _errorDetail(error);
        if (_isPermanentClientError(statusCode)) {
          await _database.markPendingExpense(
            clientOperationId: expense.clientOperationId,
            status: 'conflict',
            lastError: detail,
          );
          conflicts += 1;
          continue;
        }
        await _database.markPendingExpense(
          clientOperationId: expense.clientOperationId,
          status: 'pending',
          lastError: detail,
        );
        if (error.response == null) networkUnavailable = true;
        break;
      }
    }

    return result.merge(
      SyncRunResult(
        attempted: attempted,
        synced: synced,
        conflicts: conflicts,
        networkUnavailable: networkUnavailable,
      ),
    );
  }

  Future<void> _cleanupDocument(String? localDocumentId) async {
    if (localDocumentId == null) return;
    final path = await _database.deletePendingDocumentIfUnreferenced(localDocumentId);
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The server transaction is already safe. Orphan cleanup can be retried later.
    }
  }

  bool _isPermanentClientError(int? statusCode) {
    return statusCode != null && statusCode >= 400 && statusCode < 500 && statusCode != 401;
  }

  String _errorDetail(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['detail'] != null) {
      return data['detail'].toString();
    }
    return error.message ?? 'Sync failed';
  }
}
