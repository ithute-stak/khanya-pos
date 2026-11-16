import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/qr/data/qr_product_label_repository.dart';
import 'package:khanya_pos/features/qr/printing/product_qr_labels.dart';

void main() {
  const productId = '12e3a456-7b89-4bcd-80d1-11a2b3344556';
  const locator = 'khanyaqr:v1:dGVzdA.c2lnbmF0dXJl';

  Map<String, dynamic> serverLabel() => {
    'kind': 'product',
    'resource_id': productId,
    'product_name': 'Rice 2kg',
    'sku': 'RICE-2',
    'qr_token': locator,
    'expires_at': '2027-11-16T06:00:00+00:00',
  };

  test('product label requests server signature, never generates a local one', () async {
    final api = ApiClient(baseUrl: 'https://api.example.test/api/v1');
    api.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        expect(options.method, 'POST');
        expect(options.path, '/qr/products/$productId/label');
        handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: serverLabel(),
        ));
      },
    ));
    final label = await QrProductLabelRepository(apiClient: api).create(productId: productId);
    expect(label.productId, productId);
    expect(label.name, 'Rice 2kg');
    expect(label.token, locator);
  });

  test('reject label returned for another product', () async {
    final api = ApiClient(baseUrl: 'https://api.example.test/api/v1');
    api.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {...serverLabel(), 'resource_id': 'ffffffff-ffff-ffff-ffff-ffffffffffff'},
      )),
    ));
    await expectLater(
      QrProductLabelRepository(apiClient: api).create(productId: productId),
      throwsFormatException,
    );
  });

  test('generate printable A4 QR-label PDF and validate copy limits', () async {
    final label = ProductQrLabel.fromJson(serverLabel());
    final bytes = await buildProductQrLabelsPdf(label, quantity: 3);
    expect(bytes.length, greaterThan(500));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    await expectLater(buildProductQrLabelsPdf(label, quantity: 0), throwsArgumentError);
    await expectLater(buildProductQrLabelsPdf(label, quantity: 101), throwsArgumentError);
  });
}
