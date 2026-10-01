import 'package:khanya_pos/core/network/api_client.dart';

class WorkforceRepository {
  WorkforceRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  Future<Map<String, dynamic>> myAttendance() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/workforce/attendance/me');
    return response.data ?? <String, dynamic>{};
  }

  Future<void> punch(String type, {String? note}) async {
    await _apiClient.dio.post('/workforce/attendance/me/punch', data: {
      'punch_type': type,
      'note': note,
    });
  }

  Future<List<Map<String, dynamic>>> shifts() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/workforce/shifts');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> attendance() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/workforce/attendance');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> staff() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/staff');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> createShift({
    required String membershipId,
    required DateTime startsAt,
    required DateTime endsAt,
    String? note,
  }) async {
    await _apiClient.dio.post('/workforce/shifts', data: {
      'membership_id': membershipId,
      'starts_at': startsAt.toUtc().toIso8601String(),
      'ends_at': endsAt.toUtc().toIso8601String(),
      'note': note,
    });
  }
}
