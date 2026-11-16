import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/qr/data/qr_resolver_repository.dart';

void main() {
  final resourceId = '12e3a456-7b89-4bcd-80d1-11a2b3344556';

  ApiClient mockClient(Map<String, dynamic> result) {
    final api = ApiClient(baseUrl: 'https://api.example.test/api/v1');
    api.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        expect(options.method, 'POST');
        expect(options.path, '/qr/resolve');
        expect(options.data, {'token': 'qr-demo-token'});
        handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options,
          data: result,
          statusCode: 200,
        ));
      },
    ));
    return api;
  }

  test('only backend-verified sale destinations can be opened', () async {
    final repository = QrResolverRepository(apiClient: mockClient({
      'verified': true,
      'kind': 'sale',
      'resource_id': resourceId,
      'destination': '/sales/$resourceId',
    }));
    final resolved = await repository.verify('qr-demo-token');
    expect(resolved.kind, 'sale');
    expect(resolved.destination, '/sales/$resourceId');
  });

  test('customer detail requires matching backend destination', () async {
    final repository = QrResolverRepository(apiClient: mockClient({
      'verified': true,
      'kind': 'customer',
      'resource_id': resourceId,
      'destination': '/customers/$resourceId',
    }));
    expect((await repository.verify('qr-demo-token')).destination,
        '/customers/$resourceId');
  });

  test('reject unverifiable responses and injected destinations', () async {
    for (final response in [
      {
        'verified': false,
        'kind': 'sale',
        'resource_id': resourceId,
        'destination': '/sales/$resourceId',
      },
      {
        'verified': true,
        'kind': 'sale',
        'resource_id': resourceId,
        'destination': 'https://attacker.example.test',
      },
      {
        'verified': true,
        'kind': 'payment_request',
        'resource_id': resourceId,
        'destination': '/pos',
      },
      {
        'verified': true,
        'kind': 'sale',
        'resource_id': 'not-a-uuid',
        'destination': '/sales/not-a-uuid',
      },
    ]) {
      final repository = QrResolverRepository(apiClient: mockClient(response));
      await expectLater(repository.verify('qr-demo-token'), throwsFormatException);
    }
  });
}
