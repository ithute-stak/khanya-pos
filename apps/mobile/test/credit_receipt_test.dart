import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/printing/sale_receipt.dart';

void main() {
  const lines = [
    SaleReceiptLine(
      name: 'Maize Meal',
      quantity: 2,
      unitPriceMinor: 4000,
      lineTotalMinor: 8000,
      sku: 'MM-01',
    ),
  ];

  test('partial customer sale exposes paid amount and remaining balance', () {
    final receipt = SaleReceipt(
      businessName: 'Khanya Test Shop',
      reference: 'sale-1',
      issuedAt: DateTime.utc(2026, 9, 21),
      lines: lines,
      paymentMethod: PaymentMethod.cash,
      syncStatus: 'Queued for sync',
      customerName: 'Mpho Traders',
      paidNowMinor: 3000,
      balanceDueMinor: 5000,
      cashTenderedMinor: 5000,
    );

    expect(receipt.totalMinor, 8000);
    expect(receipt.paidMinor, 3000);
    expect(receipt.creditBalanceMinor, 5000);
    expect(receipt.isCreditSale, isTrue);
    expect(receipt.cashChangeMinor, 2000);
  });

  test('full-credit sale has no cash change and keeps full balance due', () {
    final receipt = SaleReceipt(
      businessName: 'Khanya Test Shop',
      reference: 'sale-2',
      issuedAt: DateTime.utc(2026, 9, 21),
      lines: lines,
      paymentMethod: PaymentMethod.cash,
      syncStatus: 'Queued for sync',
      customerName: 'Mpho Traders',
      paidNowMinor: 0,
      balanceDueMinor: 8000,
    );

    expect(receipt.paidMinor, 0);
    expect(receipt.creditBalanceMinor, 8000);
    expect(receipt.isCreditSale, isTrue);
    expect(receipt.cashChangeMinor, isNull);
  });

  test('normal cash sale remains fully paid', () {
    final receipt = SaleReceipt(
      businessName: 'Khanya Test Shop',
      reference: 'sale-3',
      issuedAt: DateTime.utc(2026, 9, 21),
      lines: lines,
      paymentMethod: PaymentMethod.cash,
      syncStatus: 'Synced',
      cashTenderedMinor: 10000,
    );

    expect(receipt.paidMinor, 8000);
    expect(receipt.creditBalanceMinor, 0);
    expect(receipt.isCreditSale, isFalse);
    expect(receipt.cashChangeMinor, 2000);
  });
}
