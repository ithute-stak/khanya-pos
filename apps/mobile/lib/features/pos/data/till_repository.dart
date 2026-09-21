import 'package:dio/dio.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/pos/domain/till_shift.dart';
import 'package:uuid/uuid.dart';

class TillRepository {
  TillRepository({required ApiClient apiClient, Uuid? uuid})
      : _apiClient = apiClient,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final Uuid _uuid;

  Future<TillShiftSummary?> current() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('/pos/till/current');
      final data = response.data;
      if (data == null) return null;
      return TillShiftSummary.fromJson(Map<String, dynamic>.from(data as Map));
    } on DioException catch (error) {
      throw StateError(_message(error, 'Unable to load the current till shift.'));
    }
  }

  Future<List<TillShiftSummary>> history({int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get<List<dynamic>>(
        '/pos/till/history',
        queryParameters: {'limit': limit},
      );
      return (response.data ?? const <dynamic>[])
          .map((value) => TillShiftSummary.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList(growable: false);
    } on DioException catch (error) {
      throw StateError(_message(error, 'Unable to load till history.'));
    }
  }

  Future<TillShiftSummary> open({required int openingFloatMinor}) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/pos/till/open',
        data: {
          'client_operation_id': _uuid.v4(),
          'opening_float': ScaledDecimal.fromMinor(openingFloatMinor),
        },
      );
      return TillShiftSummary.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (error) {
      throw StateError(_message(error, 'Unable to open the till shift.'));
    }
  }

  Future<TillShiftSummary> cashMovement({
    required String movementType,
    required int amountMinor,
    required String reason,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/pos/till/cash-movements',
        data: {
          'client_operation_id': _uuid.v4(),
          'movement_type': movementType,
          'amount': ScaledDecimal.fromMinor(amountMinor),
          'reason': reason.trim(),
        },
      );
      return TillShiftSummary.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (error) {
      throw StateError(_message(error, 'Unable to record the cash movement.'));
    }
  }

  Future<TillShiftSummary> close({
    required String shiftId,
    required int countedCashMinor,
    String? note,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/pos/till/close',
        data: {
          'shift_id': shiftId,
          'counted_cash': ScaledDecimal.fromMinor(countedCashMinor),
          'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
        },
      );
      return TillShiftSummary.fromJson(response.data ?? const <String, dynamic>{});
    } on DioException catch (error) {
      throw StateError(_message(error, 'Unable to close the till shift.'));
    }
  }

  String _message(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map && data['detail'] != null) return data['detail'].toString();
    return fallback;
  }
}
