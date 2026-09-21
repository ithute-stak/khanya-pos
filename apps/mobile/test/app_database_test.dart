import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/storage/app_database.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('offline sale is queued and stock is reduced atomically', () async {
    final now = DateTime.utc(2026, 9, 21);
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [
        CachedProductsCompanion.insert(
          productId: 'product-1',
          tenantId: 'tenant-1',
          branchId: 'branch-1',
          name: 'Maize Meal',
          sku: 'MM001',
          sellingPriceMinor: 3800,
          costPriceMinor: 3000,
          onHandMilli: const Value(10000),
          updatedAt: now,
        ),
      ],
    );

    await database.queueSaleAndApplyStock(
      sale: PendingSalesCompanion.insert(
        clientOperationId: '00000000-0000-4000-8000-000000000001',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        payloadJson: '{}',
        createdAt: now,
        updatedAt: now,
      ),
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      stockChanges: const [LocalSaleStockChange(productId: 'product-1', quantityMilli: 2000)],
    );

    final products = await database.getProducts(tenantId: 'tenant-1', branchId: 'branch-1');
    expect(products.single.onHandMilli, 8000);
    expect(
      await database.getPendingSale('00000000-0000-4000-8000-000000000001'),
      isA<PendingSale>(),
    );
  });

  test('replaying the same local operation does not deduct stock twice', () async {
    final now = DateTime.utc(2026, 9, 21);
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [
        CachedProductsCompanion.insert(
          productId: 'product-1',
          tenantId: 'tenant-1',
          branchId: 'branch-1',
          name: 'Sugar',
          sku: 'SUG001',
          sellingPriceMinor: 3200,
          costPriceMinor: 2600,
          onHandMilli: const Value(5000),
          updatedAt: now,
        ),
      ],
    );
    final sale = PendingSalesCompanion.insert(
      clientOperationId: '00000000-0000-4000-8000-000000000002',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      payloadJson: '{}',
      createdAt: now,
      updatedAt: now,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await database.queueSaleAndApplyStock(
        sale: sale,
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        stockChanges: const [LocalSaleStockChange(productId: 'product-1', quantityMilli: 1000)],
      );
    }
    final products = await database.getProducts(tenantId: 'tenant-1', branchId: 'branch-1');
    expect(products.single.onHandMilli, 4000);
  });
}
