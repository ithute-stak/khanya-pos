import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/storage/app_database.dart';

class SyncRunResult {
  const SyncRunResult({
    required this.attempted,
    required this.synced,
    required this.conflicts,
    required this.networkUnavailable,
  });

  final int attempted;
  final int synced;
  final int conflicts;
  final bool networkUnavailable;
}

class SyncService {
  SyncService({required ApiClient apiClient, required AppDatabase database})
      : _apiClient = apiClient,
        _database = database;

  final ApiClient _apiClient;
  final AppDatabase _database;

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
        await _database.deletePendingSale(sale.clientOperationId);
        synced += 1;
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        final detail = _errorDetail(error);
        if (statusCode != null && statusCode >= 400 && statusCode < 500 && statusCode != 401) {
          await _database.markPendingSale(
            clientOperationId: sale.clientOperationId,
            status: 'conflict',
            lastError: detail,
          );
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

  String _errorDetail(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['detail'] != null) {
      return data['detail'].toString();
    }
    return error.message ?? 'Sync failed';
  }
}
