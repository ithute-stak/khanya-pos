import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/qr/data/qr_sale_receipt_repository.dart';
import 'package:khanya_pos/features/qr/printing/signed_receipt_qr_pdf.dart';

void main() {
  const saleId = '12e3a456-7b89-4bcd-80d1-11a2b3344556';
  const token = 'khanyaqr:v1:c2FsZQ.c2lnbmF0dXJl';

  Map<String, dynamic> payload() => {
    'kind': 'receipt',
    'sale_id': saleId,
    'sale_number': 'SL-2026-0042',
    'qr_token': token,
    'expires_at': '2027-11-16T06:00:00+00:00',
  };

  test('requests a signed receipt from authenticated backend', () async {
    final client = ApiClient(baseUrl: 'https://example.test/api/v1');
    client.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        expect(options.method, 'POST');
        expect(options.path, '/qr/sales/$saleId/receipt');
        handler.resolve(Response<Map<String, dynamic>>(
          requestOptions: options, data: payload(), statusCode: 200,
        ));
      },
    ));
    final label = await QrSaleReceiptRepository(apiClient: client).issue(saleId);
    expect(label.saleId, saleId);
    expect(label.token, token);
  });

  test('mismatched sale identity is rejected', () async {
    final client = ApiClient(baseUrl: 'https://example.test/api/v1');
    client.dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options, data: {...payload(), 'sale_id': 'other'},
          statusCode: 200,
        ),
      ),
    ));
    await expectLater(
      QrSaleReceiptRepository(apiClient: client).issue(saleId),
      throwsFormatException,
    );
  });

  test('receipt QR lookup slip is a PDF, not a payment confirmation', () async {
    final bytes = await buildSignedReceiptQrPdf(SignedSaleReceiptQr.fromJson(payload()));
    expect(bytes.length, greaterThan(500));
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
  });
}
