import 'package:equatable/equatable.dart';

class BusinessBranch extends Equatable {
  const BusinessBranch({
    required this.id,
    required this.name,
    required this.code,
    this.location,
    this.isMain = false,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String code;
  final String? location;
  final bool isMain;
  final bool isActive;

  factory BusinessBranch.fromJson(Map<String, dynamic> json) => BusinessBranch(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? 'Branch',
        code: json['code']?.toString() ?? '',
        location: json['location']?.toString(),
        isMain: json['is_main'] == true,
        isActive: json['is_active'] != false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'location': location,
        'is_main': isMain,
        'is_active': isActive,
      };

  @override
  List<Object?> get props => [id, name, code, location, isMain, isActive];
}

class BusinessMembership extends Equatable {
  const BusinessMembership({
    required this.tenantId,
    required this.tenantName,
    required this.tenantSlug,
    required this.role,
    required this.branchIds,
    this.branches = const [],
  });

  final String tenantId;
  final String tenantName;
  final String tenantSlug;
  final String role;
  final List<String> branchIds;
  final List<BusinessBranch> branches;

  BusinessBranch? branchById(String? branchId) {
    if (branchId == null) return null;
    for (final branch in branches) {
      if (branch.id == branchId) return branch;
    }
    return null;
  }

  String branchLabel(String branchId, {int? fallbackIndex}) {
    final branch = branchById(branchId);
    if (branch != null) {
      final code = branch.code.trim();
      return code.isEmpty ? branch.name : '${branch.name} ($code)';
    }
    return fallbackIndex == null ? 'Branch' : 'Branch ${fallbackIndex + 1}';
  }

  factory BusinessMembership.fromJson(Map<String, dynamic> json) {
    return BusinessMembership(
      tenantId: json['tenant_id'].toString(),
      tenantName: json['tenant_name'].toString(),
      tenantSlug: json['tenant_slug'].toString(),
      role: json['role'].toString(),
      branchIds: (json['branch_ids'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      branches: (json['branches'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((value) => BusinessBranch.fromJson(Map<String, dynamic>.from(value)))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'tenant_name': tenantName,
        'tenant_slug': tenantSlug,
        'role': role,
        'branch_ids': branchIds,
        'branches': branches.map((branch) => branch.toJson()).toList(growable: false),
      };

  @override
  List<Object?> get props => [tenantId, tenantName, tenantSlug, role, branchIds, branches];
}

class AuthSession extends Equatable {
  const AuthSession({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.memberships,
    this.isPlatformAdmin = false,
    this.platformRole,
    this.selectedTenantId,
    this.selectedBranchId,
  });

  final String userId;
  final String displayName;
  final String email;
  final String accessToken;
  final String refreshToken;
  final List<BusinessMembership> memberships;
  final bool isPlatformAdmin;
  final String? platformRole;
  final String? selectedTenantId;
  final String? selectedBranchId;

  bool get canOperatePlatform =>
      platformRole == 'platform_super_admin' || platformRole == 'platform_admin';
  bool get isPlatformSuperAdmin => platformRole == 'platform_super_admin';

  AuthSession selectBusiness({required String tenantId, String? branchId}) {
    return AuthSession(
      userId: userId,
      displayName: displayName,
      email: email,
      accessToken: accessToken,
      refreshToken: refreshToken,
      memberships: memberships,
      isPlatformAdmin: isPlatformAdmin,
      platformRole: platformRole,
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
      isPlatformAdmin: isPlatformAdmin,
      platformRole: platformRole,
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
        'is_platform_admin': isPlatformAdmin,
        'platform_role': platformRole,
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
      isPlatformAdmin: json['is_platform_admin'] == true,
      platformRole: json['platform_role']?.toString(),
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
        isPlatformAdmin,
        platformRole,
        selectedTenantId,
        selectedBranchId,
      ];
}
