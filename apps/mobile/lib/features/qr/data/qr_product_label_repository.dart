import 'package:khanya_pos/core/network/api_client.dart';

class ProductQrLabel {
  const ProductQrLabel({
    required this.productId,
    required this.name,
    required this.sku,
    required this.token,
    required this.expiresAt,
  });

  final String productId;
  final String name;
  final String sku;
  final String token;
  final DateTime expiresAt;

  factory ProductQrLabel.fromJson(Map<String, dynamic> json) {
    if (json['kind'] != 'product' ||
        json['resource_id'] is! String ||
        json['product_name'] is! String ||
        json['sku'] is! String ||
        json['qr_token'] is! String ||
        json['expires_at'] is! String) {
      throw const FormatException('Unexpected product QR label response');
    }
    final token = json['qr_token'] as String;
    if (!token.startsWith('khanyaqr:v1:') || token.length > 1200) {
      throw const FormatException('Invalid product QR locator');
    }
    return ProductQrLabel(
      productId: json['resource_id'] as String,
      name: json['product_name'] as String,
      sku: json['sku'] as String,
      token: token,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class QrProductLabelRepository {
  const QrProductLabelRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<ProductQrLabel> create({required String productId}) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/qr/products/$productId/label',
    );
    final label = ProductQrLabel.fromJson(response.data ?? const {});
    if (label.productId != productId) {
      throw const FormatException('Product label identity does not match request');
    }
    return label;
  }
}
