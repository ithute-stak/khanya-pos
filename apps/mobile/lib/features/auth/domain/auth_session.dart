import 'package:equatable/equatable.dart';

class BusinessMembership extends Equatable {
  const BusinessMembership({
    required this.tenantId,
    required this.tenantName,
    required this.tenantSlug,
    required this.role,
    required this.branchIds,
  });

  final String tenantId;
  final String tenantName;
  final String tenantSlug;
  final String role;
  final List<String> branchIds;

  @override
  List<Object?> get props => [tenantId, tenantName, tenantSlug, role, branchIds];
}

class AuthSession extends Equatable {
  const AuthSession({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.memberships,
    this.selectedTenantId,
    this.selectedBranchId,
  });

  final String userId;
  final String displayName;
  final String email;
  final String accessToken;
  final String refreshToken;
  final List<BusinessMembership> memberships;
  final String? selectedTenantId;
  final String? selectedBranchId;

  AuthSession selectBusiness({required String tenantId, String? branchId}) {
    return AuthSession(
      userId: userId,
      displayName: displayName,
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      memberships: memberships,
      selectedTenantId: tenantId,
      selectedBranchId: branchId,
    );
  }

  Map<String, String> get requestHeaders {
    final headers = <String, String>{'Authorization': 'Bearer $accessToken'};
    if (selectedTenantId != null) headers['X-Tenant-ID'] = selectedTenantId!;
    if (selectedBranchId != null) headers['X-Branch-ID'] = selectedBranchId!;
    return headers;
  }

  @override
  List<Object?> get props => [
        userId,
        displayName,
        email,
        accessToken,
        refreshToken,
        memberships,
        selectedTenantId,
        selectedBranchId,
      ];
}
