import 'package:khanya_pos/core/network/api_client.dart';

class PurchaseOrderRepository {
  PurchaseOrderRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Map<String, dynamic>>> list() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/purchase-orders');
    return (response.data ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> detail(String id) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/purchase-orders/$id');
    return response.data ?? const <String, dynamic>{};
  }

  Future<void> create({
    required String supplierId,
    DateTime? expectedAt,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    await _apiClient.dio.post<void>(
      '/purchase-orders',
      data: <String, dynamic>{
        'supplier_id': supplierId,
        'expected_at': expectedAt?.toUtc().toIso8601String(),
        'notes': notes,
        'items': items,
      },
    );
  }

  Future<void> approve(String id) => _apiClient.dio.post<void>('/purchase-orders/$id/approve');

  Future<void> cancel(String id) => _apiClient.dio.post<void>('/purchase-orders/$id/cancel');

  Future<void> receive({
    required String id,
    String? supplierInvoiceNumber,
    String paymentMethod = 'supplier_credit',
    String amountPaid = '0.00',
    String? notes,
  }) async {
    await _apiClient.dio.post<void>(
      '/purchase-orders/$id/receive',
      data: <String, dynamic>{
        'supplier_invoice_number': supplierInvoiceNumber,
        'payment_method': paymentMethod,
        'amount_paid': amountPaid,
        'notes': notes,
      },
    );
  }
}
