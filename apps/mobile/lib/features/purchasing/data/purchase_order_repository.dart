import 'package:khanya_pos/core/network/api_client.dart';

class PurchaseOrderRepository {
  PurchaseOrderRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  Future<List<Map<String, dynamic>>> list() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/purchase-orders');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> suppliers() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/suppliers');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> products() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/products');
    return (response.data ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> create({
    required String supplierId,
    required String productId,
    required double quantity,
    required double unitCost,
    double taxTotal = 0,
    String? notes,
  }) async {
    await _apiClient.dio.post('/purchase-orders', data: {
      'supplier_id': supplierId,
      'notes': notes,
      'lines': [
        {
          'product_id': productId,
          'quantity': quantity,
          'unit_cost': unitCost,
          'tax_total': taxTotal,
        }
      ],
    });
  }

  Future<void> updateStatus(String orderId, String status) async {
    await _apiClient.dio.patch('/purchase-orders/$orderId/status', data: {'status': status});
  }
}
