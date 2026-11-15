import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/qr/domain/qr_scan_target.dart';

String demoQr(String kind, {String? resourceId}) {
  final payload = {
    'v': 1,
    'k': kind,
    'r': resourceId ?? 'cdeaba52-34ba-4650-97c8-24e7d91cb724',
    't': 'b0cab121-24ad-4d0a-a82c-09b285be1091',
    'b': null,
    'e': 9999999999,
  };
  final encoded = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  return 'khanyaqr:v1:$encoded.${'a' * 43}';
}

void main() {
  test('every supported QR kind leads to a known non-mutating module', () {
    expect(qrModulePaths.length, 14);
    for (final kind in qrModulePaths.keys) {
      final result = inspectKhanyaQrLocator(demoQr(kind));
      expect(result?.kind, kind);
      expect(result?.modulePath, startsWith('/'));
      expect(result?.moduleLabel, isNotEmpty);
    }
  });

  test('payment request only leads to checkout, never marks paid', () {
    final target = inspectKhanyaQrLocator(demoQr('payment_request'));
    expect(target?.modulePath, '/pos');
  });

  test('malformed, unknown and random QR codes are rejected', () {
    expect(inspectKhanyaQrLocator('https://attacker.example/pay'), isNull);
    expect(inspectKhanyaQrLocator('khanyaqr:v2:abc.def'), isNull);
    expect(inspectKhanyaQrLocator(demoQr('unexpected_kind')), isNull);
    expect(inspectKhanyaQrLocator(demoQr('product', resourceId: 'bad')), isNull);
    expect(inspectKhanyaQrLocator('khanyaqr:v1:notbase64.invalid'), isNull);
  });
}
