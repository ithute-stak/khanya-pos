import 'package:khanya_pos/core/network/api_client.dart';

/// Backend-verification result. Only the server may choose a deep link.
class VerifiedQrDestination {
  const VerifiedQrDestination({
    required this.kind,
    required this.resourceId,
    required this.destination,
  });

  final String kind;
  final String resourceId;
  final String destination;
}

class QrResolverRepository {
  const QrResolverRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<VerifiedQrDestination> verify(String token) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/qr/resolve',
      data: {'token': token},
    );
    final data = response.data;
    if (data == null || data['verified'] != true) {
      throw const FormatException('QR response was not verified');
    }
    final kind = data['kind'];
    final resourceId = data['resource_id'];
    final destination = data['destination'];
    if (kind is! String || resourceId is! String || destination is! String) {
      throw const FormatException('Unexpected QR response');
    }
    const allowed = {'product', 'sale', 'receipt', 'customer'};
    final uuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    if (!allowed.contains(kind) || !uuid.hasMatch(resourceId)) {
      throw const FormatException('Unsupported QR destination');
    }
    final expected = switch (kind) {
      'sale' || 'receipt' => '/sales/$resourceId',
      'customer' => '/customers/$resourceId',
      _ => '/products',
    };
    if (destination != expected) {
      throw const FormatException('Invalid QR navigation destination');
    }
    return VerifiedQrDestination(
      kind: kind,
      resourceId: resourceId,
      destination: destination,
    );
  }
}
