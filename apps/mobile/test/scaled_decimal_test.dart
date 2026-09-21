import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

void main() {
  test('money parsing stays in integer minor units', () {
    expect(ScaledDecimal.toMinor('38.00'), 3800);
    expect(ScaledDecimal.toMinor('0.10'), 10);
    expect(ScaledDecimal.toMinor('-12.34'), -1234);
    expect(ScaledDecimal.fromMinor(123456), '1234.56');
    expect(Loti.formatMinor(123456), 'M 1,234.56');
  });

  test('inventory quantities use thousandths without doubles', () {
    expect(ScaledDecimal.toMilli('12.345'), 12345);
    expect(ScaledDecimal.fromMilli(12000), '12');
    expect(ScaledDecimal.fromMilli(12500), '12.5');
  });
}
