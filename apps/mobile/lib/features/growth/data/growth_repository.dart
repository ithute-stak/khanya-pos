import 'package:khanya_pos/core/network/api_client.dart';

class GrowthRepository {
  GrowthRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  Future<List<Map<String, dynamic>>> promotions() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/growth/promotions');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> createPromotion({
    required String name,
    required String code,
    required String discountType,
    required double value,
    required double minimumSpend,
  }) async {
    await _apiClient.dio.post('/growth/promotions', data: {
      'name': name,
      'code': code,
      'discount_type': discountType,
      'value': value,
      'minimum_spend': minimumSpend,
    });
  }

  Future<List<Map<String, dynamic>>> documents() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/growth/documents');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> createDocument({
    required String documentType,
    String? customerId,
    required String customerName,
    String? customerEmail,
    required String description,
    required double quantity,
    required double unitPrice,
    String currency = 'LSL',
  }) async {
    await _apiClient.dio.post('/growth/documents', data: {
      'document_type': documentType,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_email': customerEmail,
      'currency': currency,
      'lines': [
        {
          'description': description,
          'quantity': quantity,
          'unit_price': unitPrice,
          'discount_amount': 0,
          'tax_amount': 0,
        }
      ],
    });
  }

  Future<List<Map<String, dynamic>>> alerts() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/growth/alerts');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> refreshAlerts() => _apiClient.dio.post('/growth/alerts/refresh');

  Future<void> updateAlert(String alertId, String status) =>
      _apiClient.dio.patch('/growth/alerts/$alertId', data: {'status': status});

  Future<List<Map<String, dynamic>>> customers() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/customers');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> loyalty(String customerId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/growth/loyalty/$customerId');
    return response.data ?? <String, dynamic>{};
  }

  Future<void> adjustLoyalty(
    String customerId, {
    required double points,
    required String transactionType,
    String? note,
  }) async {
    await _apiClient.dio.post('/growth/loyalty/$customerId/transactions', data: {
      'points': points,
      'transaction_type': transactionType,
      'note': note,
    });
  }
}
