import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/qr/data/qr_customer_card_repository.dart';
import 'package:khanya_pos/features/qr/printing/customer_qr_card_pdf.dart';

void main() {
  const customerId = '12e3a456-7b89-4bcd-80d1-11a2b3344556';
  const token = 'khanyaqr:v1:Y3VzdG9tZXI.c2lnbmF0dXJl';

  Map<String, dynamic> payload() => {
    'kind': 'customer',
    'customer_id': customerId,
    'customer_name': 'Customer Example',
    'customer_code': 'C-42',
    'qr_token': token,
    'expires_at': '2026-12-16T08:00:00+00:00',
  };

  test('fetch signed customer card from backend', () async {
    final api = ApiClient(baseUrl: 'https://example.test/api/v1');
    api.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        expect(options.method, 'POST');
        expect(options.path, '/qr/customers/$customerId/card');
        handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: payload(),
        ));
      },
    ));
    final card = await QrCustomerCardRepository(apiClient: api).issue(customerId);
    expect(card.customerId, customerId);
    expect(card.token, token);
    expect(card.customerCode, 'C-42');
  });

  test('reject a customer QR response for a different customer', () async {
    final api = ApiClient(baseUrl: 'https://example.test/api/v1');
    api.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {...payload(), 'customer_id': 'another'},
        ),
      ),
    ));
    await expectLater(
      QrCustomerCardRepository(apiClient: api).issue(customerId),
      throwsFormatException,
    );
  });

  test('customer QR lookup card renders to PDF', () async {
    final card = SignedCustomerQrCard.fromJson(payload());
    final bytes = await buildCustomerQrCardPdf(card);
    expect(bytes.length, greaterThan(500));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
}
