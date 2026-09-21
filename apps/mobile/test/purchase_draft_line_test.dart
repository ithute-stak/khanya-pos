import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';

void main() {
  test('purchase draft line calculates money without binary floating point', () {
    const product = ProductSummary(
      id: 'p1',
      name: 'Cooking Oil',
      sku: 'OIL1',
      unit: 'bottle',
      sellingPriceMinor: 5200,
      costPriceMinor: 4200,
      reorderLevelMilli: 2000,
      tracksStock: true,
      isLowStock: false,
    );
    const line = PurchaseDraftLine(
      product: product,
      quantityMilli: 5500,
      unitCostMinor: 4200,
    );

    expect(line.lineTotalMinor, 23100);
  });
}
