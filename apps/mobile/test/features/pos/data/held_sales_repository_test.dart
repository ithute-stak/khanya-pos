import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/pos/data/held_sales_repository.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';

void main() {
  test('held sale round-trips through JSON without losing branch or cart data', () {
    final held = HeldSale(
      id: 'held-1',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      label: 'Table 4',
      createdAt: DateTime.utc(2026, 9, 21, 15, 5),
      paymentMethod: PaymentMethod.cash,
      lines: const [
        HeldSaleLine(productId: 'bread', quantity: 2),
        HeldSaleLine(productId: 'milk', quantity: 1),
      ],
      itemCount: 3,
      totalMinor: 4800,
    );

    final restored = HeldSale.fromJson(held.toJson());

    expect(restored.id, held.id);
    expect(restored.tenantId, held.tenantId);
    expect(restored.branchId, held.branchId);
    expect(restored.label, held.label);
    expect(restored.paymentMethod, PaymentMethod.cash);
    expect(restored.itemCount, 3);
    expect(restored.totalMinor, 4800);
    expect(restored.lines, hasLength(2));
    expect(restored.lines.first.productId, 'bread');
    expect(restored.lines.first.quantity, 2);
  });

  test('unknown payment method safely falls back to cash', () {
    final held = HeldSale.fromJson({
      'id': 'held-2',
      'tenant_id': 'tenant-1',
      'branch_id': 'branch-1',
      'label': 'Unknown tender',
      'created_at': '2026-09-21T15:05:00Z',
      'payment_method': 'future_method',
      'item_count': 1,
      'total_minor': 1000,
      'lines': [
        {'product_id': 'item-1', 'quantity': 1},
      ],
    });

    expect(held.paymentMethod, PaymentMethod.cash);
    expect(held.lines.single.productId, 'item-1');
  });
}
