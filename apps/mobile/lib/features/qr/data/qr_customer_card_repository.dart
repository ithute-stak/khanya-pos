import 'package:khanya_pos/core/network/api_client.dart';

class SignedCustomerQrCard {
  const SignedCustomerQrCard({
    required this.customerId,
    required this.customerName,
    required this.customerCode,
    required this.token,
    required this.expiresAt,
  });
  final String customerId;
  final String customerName;
  final String customerCode;
  final String token;
  final DateTime expiresAt;

  factory SignedCustomerQrCard.fromJson(Map<String, dynamic> json) {
    if (json['kind'] != 'customer' ||
        json['customer_id'] is! String ||
        json['customer_name'] is! String ||
        json['customer_code'] is! String ||
        json['qr_token'] is! String ||
        json['expires_at'] is! String) {
      throw const FormatException('Invalid customer QR card response');
    }
    final token = json['qr_token'] as String;
    if (!token.startsWith('khanyaqr:v1:') || token.length > 1200) {
      throw const FormatException('Unrecognized customer QR card');
    }
    return SignedCustomerQrCard(
      customerId: json['customer_id'] as String,
      customerName: json['customer_name'] as String,
      customerCode: json['customer_code'] as String,
      token: token,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }
}

class QrCustomerCardRepository {
  const QrCustomerCardRepository({required ApiClient apiClient}) : _apiClient = apiClient;
  final ApiClient _apiClient;

  Future<SignedCustomerQrCard> issue(String customerId) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/qr/customers/$customerId/card',
    );
    final card = SignedCustomerQrCard.fromJson(response.data ?? const {});
    if (card.customerId != customerId) {
      throw const FormatException('Customer QR identity mismatch');
    }
    return card;
  }
}
