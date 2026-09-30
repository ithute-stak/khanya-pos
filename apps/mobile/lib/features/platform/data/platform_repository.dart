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

  Future<List<Map<String, dynamic>>> notifications() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/platform/notifications');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> staff() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/platform/staff');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> setStaffRole({required String email, required String? role}) async {
    await _apiClient.dio.put<void>(
      '/platform/staff/role',
      data: <String, dynamic>{'email': email.trim(), 'role': role},
    );
  }

  Future<List<Map<String, dynamic>>> subscriptions() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/subscriptions/platform');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> updateSubscription({
    required String tenantId,
    String? plan,
    String? status,
    DateTime? currentPeriodEnd,
    DateTime? graceEndsAt,
    String? billingReference,
    String? notes,
  }) async {
    await _apiClient.dio.patch<void>(
      '/subscriptions/platform/$tenantId',
      data: <String, dynamic>{
        if (plan != null) 'plan': plan,
        if (status != null) 'status': status,
        if (currentPeriodEnd != null) 'current_period_end': currentPeriodEnd.toUtc().toIso8601String(),
        if (graceEndsAt != null) 'grace_ends_at': graceEndsAt.toUtc().toIso8601String(),
        if (billingReference != null) 'billing_reference': billingReference,
        if (notes != null) 'notes': notes,
      },
    );
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
