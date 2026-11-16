import 'package:khanya_pos/core/network/api_client.dart';

class SignedSaleReceiptQr {
  const SignedSaleReceiptQr({
    required this.saleId,
    required this.saleNumber,
    required this.token,
    required this.expiresAt,
  });

  final String saleId;
  final String saleNumber;
  final String token;
  final DateTime expiresAt;

  factory SignedSaleReceiptQr.fromJson(Map<String, dynamic> json) {
    if (json['kind'] != 'receipt' ||
        json['sale_id'] is! String ||
        json['sale_number'] is! String ||
        json['qr_token'] is! String ||
        json['expires_at'] is! String) {
      throw const FormatException('Invalid signed receipt QR response');
    }
    final token = json['qr_token'] as String;
    if (!token.startsWith('khanyaqr:v1:') || token.length > 1200) {
      throw const FormatException('Unrecognized receipt QR format');
    }
    return SignedSaleReceiptQr(
      saleId: json['sale_id'] as String,
      saleNumber: json['sale_number'] as String,
      token: token,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class QrSaleReceiptRepository {
  const QrSaleReceiptRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  Future<SignedSaleReceiptQr> issue(String saleId) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/qr/sales/$saleId/receipt',
    );
    final receipt = SignedSaleReceiptQr.fromJson(response.data ?? const {});
    if (receipt.saleId != saleId) {
      throw const FormatException('Receipt QR sale identity mismatch');
    }
    return receipt;
  }
}
