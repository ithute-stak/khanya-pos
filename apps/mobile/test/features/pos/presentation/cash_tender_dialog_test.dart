import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/pos/presentation/cash_tender_dialog.dart';

void main() {
  test('quick tender amounts include exact and useful rounded values', () {
    final amounts = buildQuickTenderAmounts(14550);

    expect(amounts.first, 14550);
    expect(amounts, contains(15000));
    expect(amounts, contains(20000));
    expect(amounts.toSet().length, amounts.length);
    expect(amounts.every((amount) => amount >= 14550), isTrue);
    expect(amounts.length, lessThanOrEqualTo(5));
  });

  test('zero total has a stable exact tender option', () {
    expect(buildQuickTenderAmounts(0), const [0]);
  });
}
