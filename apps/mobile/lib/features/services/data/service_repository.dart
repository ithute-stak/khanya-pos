import 'dart:math';

import 'package:khanya_pos/core/network/api_client.dart';

class ServiceEntry {
  const ServiceEntry({required this.id, required this.name, required this.code, required this.price, this.category, this.description, this.durationMinutes, required this.isActive});

  final String id;
  final String name;
  final String code;
  final String price;
  final String? category;
  final String? description;
  final int? durationMinutes;
  final bool isActive;

  factory ServiceEntry.fromJson(Map<String, dynamic> json) => ServiceEntry(
    id: json['id'].toString(),
    name: json['name'].toString(),
    code: json['code'].toString(),
    price: json['price'].toString(),
    category: json['category']?.toString(),
    description: json['description']?.toString(),
    durationMinutes: json['duration_minutes'] as int?,
    isActive: json['is_active'] == true,
  );
}

class ServiceRepository {
  ServiceRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  static String newOperationId() {
    final random = Random.secure();
    String part(int count) => List.generate(count, (_) => random.nextInt(16).toRadixString(16)).join();
    return '${part(8)}-${part(4)}-4${part(3)}-a${part(3)}-${part(12)}';
  }

  Future<Map<String, dynamic>> checkout({required String operationId, required String serviceId, required int quantity, required String method, required String amount, String? customerId}) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>('/pos/services/complete', data: {
      'client_operation_id': operationId,
      'items': [{'service_id': serviceId, 'quantity': quantity}],
      'payments': [{'method': method, 'amount': amount}],
      if (customerId != null) 'customer_id': customerId,
    });
    return response.data ?? {};
  }

  Future<List<Map<String, dynamic>>> appointments() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/appointments');
    return (response.data ?? []).map((item) => (item as Map).cast<String, dynamic>()).toList();
  }

  Future<void> createAppointment({required String serviceId, required String customerName, required DateTime startsAt, String? membershipId}) async {
    await _apiClient.dio.post('/appointments', data: {
      'service_id': serviceId, 'customer_name': customerName.trim(),
      'starts_at': startsAt.toUtc().toIso8601String(),
      if (membershipId != null) 'membership_id': membershipId,
    });
  }

  Future<void> updateAppointmentStatus(String id, String status) async {
    await _apiClient.dio.patch('/appointments/$id', data: {'status': status});
  }

  Future<List<ServiceEntry>> list() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/services');
    return (response.data ?? []).map((row) => ServiceEntry.fromJson((row as Map).cast<String, dynamic>())).toList();
  }

  Future<void> save({String? id, required String name, required String code, required String price, String? category, String? description, int? durationMinutes, bool isActive = true}) async {
    final data = {
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'price': price.trim(),
      'category': category?.trim().isEmpty == true ? null : category?.trim(),
      'description': description?.trim().isEmpty == true ? null : description?.trim(),
      'duration_minutes': durationMinutes,
      'is_active': isActive,
    };
    if (id == null) {
      await _apiClient.dio.post('/services', data: data);
    } else {
      await _apiClient.dio.put('/services/$id', data: data);
    }
  }
}
