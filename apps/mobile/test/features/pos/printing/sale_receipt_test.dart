import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/printing/sale_receipt.dart';

void main() {
  test('buildSaleReceiptPdf creates a valid PDF document', () async {
    final receipt = SaleReceipt(
      businessName: 'Test Retailer',
      reference: 'sale-operation-1234567890',
      issuedAt: DateTime.utc(2026, 9, 21, 13, 30),
      branchId: 'branch-1',
      cashierName: 'Cashier One',
      paymentMethod: PaymentMethod.cash,
      syncStatus: 'Synced',
      lines: const [
        SaleReceiptLine(
          name: 'Bread',
          sku: 'BR-001',
          quantity: 2,
          unitPriceMinor: 1500,
          lineTotalMinor: 3000,
        ),
        SaleReceiptLine(
          name: 'Milk',
          sku: 'ML-002',
          quantity: 1,
          unitPriceMinor: 1800,
          lineTotalMinor: 1800,
        ),
      ],
    );

    final bytes = await buildSaleReceiptPdf(receipt);

    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(receipt.totalMinor, 4800);
    expect(formatMalotiMinor(receipt.totalMinor), 'M 48.00');
  });
}
