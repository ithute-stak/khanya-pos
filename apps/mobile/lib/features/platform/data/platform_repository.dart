import 'package:khanya_pos/core/network/api_client.dart';

class PlatformRepository {
  PlatformRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<Map<String, dynamic>> summary() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/platform/summary');
    return response.data ?? const <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> pendingApplications() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/platform/onboarding/notifications');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> tenants() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/platform/tenants');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> dailyActivity() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/platform/activity/daily');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> tenantActivity(String tenantId) async {
    final response = await _apiClient.dio.get<List<dynamic>>('/platform/activity/$tenantId');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> approve(String tenantId) async {
    await _apiClient.dio.post<void>('/platform/onboarding/$tenantId/approve');
  }

  Future<void> reject(String tenantId, String reason) async {
    await _apiClient.dio.post<void>(
      '/platform/onboarding/$tenantId/reject',
      data: {'reason': reason.trim()},
    );
  }

  Future<void> suspend(String tenantId, String reason) async {
    await _apiClient.dio.post<void>(
      '/platform/tenants/$tenantId/suspend',
      data: {'reason': reason.trim()},
    );
  }

  Future<void> reactivate(String tenantId) async {
    await _apiClient.dio.post<void>('/platform/tenants/$tenantId/reactivate');
  }
}
