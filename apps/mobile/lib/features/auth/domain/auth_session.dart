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

  factory BusinessMembership.fromJson(Map<String, dynamic> json) {
    return BusinessMembership(
      tenantId: json['tenant_id'].toString(),
      tenantName: json['tenant_name'].toString(),
      tenantSlug: json['tenant_slug'].toString(),
      role: json['role'].toString(),
      branchIds: (json['branch_ids'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'tenant_name': tenantName,
        'tenant_slug': tenantSlug,
        'role': role,
        'branch_ids': branchIds,
      };

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

  AuthSession withTokens({required String accessToken, required String refreshToken}) {
    return AuthSession(
      userId: userId,
      displayName: displayName,
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      memberships: memberships,
      selectedTenantId: selectedTenantId,
      selectedBranchId: selectedBranchId,
    );
  }

  Map<String, String> get requestHeaders {
    final headers = <String, String>{'Authorization': 'Bearer $accessToken'};
    if (selectedTenantId != null) headers['X-Tenant-ID'] = selectedTenantId!;
    if (selectedBranchId != null) headers['X-Branch-ID'] = selectedBranchId!;
    return headers;
  }

  Map<String, dynamic> toProfileJson() => {
        'user_id': userId,
        'display_name': displayName,
        'email': email,
        'memberships': memberships.map((membership) => membership.toJson()).toList(),
        'selected_tenant_id': selectedTenantId,
        'selected_branch_id': selectedBranchId,
      };

  factory AuthSession.fromProfileJson(
    Map<String, dynamic> json, {
    required String accessToken,
    required String refreshToken,
  }) {
    return AuthSession(
      userId: json['user_id'].toString(),
      displayName: json['display_name'].toString(),
      email: json['email'].toString(),
      accessToken: accessToken,
      refreshToken: refreshToken,
      memberships: (json['memberships'] as List<dynamic>? ?? const [])
          .map((value) => BusinessMembership.fromJson(value as Map<String, dynamic>))
          .toList(growable: false),
      selectedTenantId: json['selected_tenant_id']?.toString(),
      selectedBranchId: json['selected_branch_id']?.toString(),
    );
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
