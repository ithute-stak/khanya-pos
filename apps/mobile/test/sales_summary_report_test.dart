import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/reports/domain/sales_summary_report.dart';

void main() {
  test('parses sales management summary amounts and product quantities', () {
    final report = SalesSummaryReport.fromJson({
      'start': '2026-09-01T00:00:00Z',
      'end': '2026-09-30T23:59:59Z',
      'sale_count': 4,
      'gross_sales': '1250.50',
      'returns_total': '50.00',
      'net_sales': '1200.50',
      'tax_total': '0.00',
      'balance_due': '200.00',
      'cost_of_goods': '600.25',
      'gross_profit': '600.25',
      'return_count': 1,
      'refunded_amount': '50.00',
      'payments': [
        {'method': 'cash', 'amount': '800.50'},
      ],
      'top_products': [
        {
          'product_id': 'p1',
          'name': 'Test product',
          'sku': 'SKU-1',
          'quantity': '2.500',
          'revenue': '250.00',
        }
      ],
    });

    expect(report.netSalesMinor, 120050);
    expect(report.grossProfitMinor, 60025);
    expect(report.payments.single.amountMinor, 80050);
    expect(report.topProducts.single.quantityMilli, 2500);
  });
}
