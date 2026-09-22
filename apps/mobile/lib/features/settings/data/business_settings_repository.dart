import 'package:khanya_pos/core/network/api_client.dart';

class BusinessSettings {
  const BusinessSettings({required this.id, required this.name, required this.slug, required this.isActive});

  final String id;
  final String name;
  final String slug;
  final bool isActive;

  factory BusinessSettings.fromJson(Map<String, dynamic> json) => BusinessSettings(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        isActive: json['is_active'] as bool? ?? true,
      );
}

class ManagedBranch {
  const ManagedBranch({
    required this.id,
    required this.name,
    required this.code,
    required this.location,
    required this.isMain,
    required this.isActive,
  });

  final String id;
  final String name;
  final String code;
  final String? location;
  final bool isMain;
  final bool isActive;

  factory ManagedBranch.fromJson(Map<String, dynamic> json) => ManagedBranch(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        location: json['location'] as String?,
        isMain: json['is_main'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
      );
}

class BusinessSettingsRepository {
  BusinessSettingsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<BusinessSettings> getBusiness() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/tenants/current');
    return BusinessSettings.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<BusinessSettings> updateBusinessName(String name) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/tenants/current',
      data: {'name': name.trim()},
    );
    return BusinessSettings.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<List<ManagedBranch>> listBranches() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/tenants/current/branches/manage');
    return (response.data ?? const <dynamic>[])
        .map((item) => ManagedBranch.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ManagedBranch> createBranch({
    required String name,
    required String code,
    required String? location,
    required bool isMain,
  }) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/tenants/current/branches',
      data: {
        'name': name.trim(),
        'code': code.trim(),
        'location': location?.trim().isEmpty == true ? null : location?.trim(),
        'is_main': isMain,
      },
    );
    return ManagedBranch.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<ManagedBranch> updateBranch({
    required ManagedBranch branch,
    required String name,
    required String code,
    required String? location,
    required bool isMain,
    required bool isActive,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/tenants/current/branches/${branch.id}',
      data: {
        'name': name.trim(),
        'code': code.trim(),
        'location': location?.trim().isEmpty == true ? null : location?.trim(),
        'is_main': isMain,
        'is_active': isActive,
      },
    );
    return ManagedBranch.fromJson(response.data ?? const <String, dynamic>{});
  }
}
