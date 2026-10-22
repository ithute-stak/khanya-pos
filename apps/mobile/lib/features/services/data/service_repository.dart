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

  Future<Map<String, dynamic>> checkout({required String serviceId, required int quantity, required String method, required String amount, String? customerId}) async {
    final random = Random.secure();
    String part(int count) => List.generate(count, (_) => random.nextInt(16).toRadixString(16)).join();
    final operationId = '${part(8)}-${part(4)}-4${part(3)}-a${part(3)}-${part(12)}';
    final response = await _apiClient.dio.post<Map<String, dynamic>>('/pos/services/complete', data: {
      'client_operation_id': operationId,
      'items': [{'service_id': serviceId, 'quantity': quantity}],
      'payments': [{'method': method, 'amount': amount}],
      if (customerId != null) 'customer_id': customerId,
    });
    return response.data ?? {};
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
