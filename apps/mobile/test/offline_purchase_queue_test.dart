import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/storage/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('queued purchase projects stock and survives catalog refresh', () async {
    final now = DateTime.utc(2026, 9, 21);
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [
        CachedProductsCompanion.insert(
          productId: 'product-1',
          tenantId: 'tenant-1',
          branchId: 'branch-1',
          name: 'Sugar 2kg',
          sku: 'SUG-2KG',
          sellingPriceMinor: 3200,
          costPriceMinor: 2500,
          updatedAt: now,
        ),
      ],
    );

    await database.queuePurchaseAndApplyStock(
      purchase: PendingPurchasesCompanion.insert(
        clientOperationId: 'purchase-1',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        payloadJson: '{}',
        createdAt: now,
        updatedAt: now,
      ),
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      stockChanges: const [
        LocalPurchaseStockChange(productId: 'product-1', quantityMilli: 5000),
      ],
    );

    var product = (await database.getProducts(tenantId: 'tenant-1', branchId: 'branch-1')).single;
    expect(product.onHandMilli, 5000);

    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [
        CachedProductsCompanion.insert(
          productId: 'product-1',
          tenantId: 'tenant-1',
          branchId: 'branch-1',
          name: 'Sugar 2kg',
          sku: 'SUG-2KG',
          sellingPriceMinor: 3200,
          costPriceMinor: 2500,
          onHandMilli: const Value(0),
          updatedAt: now,
        ),
      ],
    );

    product = (await database.getProducts(tenantId: 'tenant-1', branchId: 'branch-1')).single;
    expect(product.onHandMilli, 5000);
  });

  test('purchase conflict releases optimistic stock', () async {
    final now = DateTime.utc(2026, 9, 21);
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [
        CachedProductsCompanion.insert(
          productId: 'product-1',
          tenantId: 'tenant-1',
          branchId: 'branch-1',
          name: 'Cooking Oil',
          sku: 'OIL-1',
          sellingPriceMinor: 5200,
          costPriceMinor: 4000,
          onHandMilli: const Value(2000),
          updatedAt: now,
        ),
      ],
    );

    await database.queuePurchaseAndApplyStock(
      purchase: PendingPurchasesCompanion.insert(
        clientOperationId: 'purchase-2',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        payloadJson: '{}',
        createdAt: now,
        updatedAt: now,
      ),
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      stockChanges: const [
        LocalPurchaseStockChange(productId: 'product-1', quantityMilli: 3000),
      ],
    );

    await database.markPendingPurchase(
      clientOperationId: 'purchase-2',
      status: 'conflict',
      lastError: 'Supplier is required',
    );

    final product = (await database.getProducts(tenantId: 'tenant-1', branchId: 'branch-1')).single;
    expect(product.onHandMilli, 2000);
  });
}
