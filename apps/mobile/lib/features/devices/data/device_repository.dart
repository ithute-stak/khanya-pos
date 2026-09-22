import 'package:khanya_pos/core/network/api_client.dart';

class ManagedDevice {
  const ManagedDevice({
    required this.id,
    required this.installationId,
    required this.branchId,
    required this.branchName,
    required this.name,
    required this.deviceType,
    required this.platform,
    required this.appVersion,
    required this.isActive,
    required this.lastSeenAt,
  });

  factory ManagedDevice.fromJson(Map<String, dynamic> json) => ManagedDevice(
        id: json['id'].toString(),
        installationId: json['installation_id']?.toString() ?? '',
        branchId: json['branch_id'].toString(),
        branchName: json['branch_name']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        deviceType: json['device_type']?.toString() ?? '',
        platform: json['platform']?.toString() ?? '',
        appVersion: json['app_version']?.toString(),
        isActive: json['is_active'] == true,
        lastSeenAt: json['last_seen_at'] == null
            ? null
            : DateTime.tryParse(json['last_seen_at'].toString())?.toLocal(),
      );

  final String id;
  final String installationId;
  final String branchId;
  final String branchName;
  final String name;
  final String deviceType;
  final String platform;
  final String? appVersion;
  final bool isActive;
  final DateTime? lastSeenAt;

  bool get recentlySeen =>
      lastSeenAt != null && DateTime.now().difference(lastSeenAt!).inMinutes <= 10;
}

class DeviceBranch {
  const DeviceBranch({required this.id, required this.name});
  factory DeviceBranch.fromJson(Map<String, dynamic> json) => DeviceBranch(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
      );
  final String id;
  final String name;
}

class DeviceRepository {
  DeviceRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  Future<List<ManagedDevice>> listDevices() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/devices');
    return (response.data ?? const <dynamic>[])
        .map((item) => ManagedDevice.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<DeviceBranch>> listBranches() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/tenants/current/branches');
    return (response.data ?? const <dynamic>[])
        .map((item) => DeviceBranch.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<ManagedDevice> updateDevice({
    required ManagedDevice device,
    required String name,
    required String branchId,
    required bool isActive,
  }) async {
    final response = await _apiClient.dio.patch<Map<String, dynamic>>(
      '/devices/${device.id}',
      data: {'name': name, 'branch_id': branchId, 'is_active': isActive},
    );
    return ManagedDevice.fromJson(response.data ?? const <String, dynamic>{});
  }
}
