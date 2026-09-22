import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/staff/domain/staff_member.dart';

class StaffRepository {
  StaffRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<StaffMember>> listStaff() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/staff');
    return (response.data ?? const <dynamic>[])
        .map((item) => StaffMember.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<StaffBranch>> listBranches() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/tenants/current/branches');
    return (response.data ?? const <dynamic>[])
        .map((item) => StaffBranch.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<StaffMember> createStaff({
    required String displayName,
    required String email,
    required String? phone,
    required String? password,
    required String role,
    required List<String> branchIds,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/staff',
      data: {
        'display_name': displayName,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        'branch_ids': branchIds,
      },
    );
    return StaffMember.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<StaffMember> updateStaff({
    required StaffMember staff,
    required String displayName,
    required String? phone,
    required String role,
    required List<String> branchIds,
    required bool isActive,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/staff/${staff.membershipId}',
      data: {
        'display_name': displayName,
        'phone': phone,
        'role': role,
        'branch_ids': branchIds,
        'is_active': isActive,
      },
    );
    return StaffMember.fromJson(response.data ?? const <String, dynamic>{});
  }
}
