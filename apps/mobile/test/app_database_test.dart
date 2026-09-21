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

  CachedProductsCompanion product({
    required String name,
    required String sku,
    required int onHandMilli,
    DateTime? updatedAt,
  }) {
    return CachedProductsCompanion.insert(
      productId: 'product-1',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      name: name,
      sku: sku,
      sellingPriceMinor: 3800,
      costPriceMinor: 3000,
      onHandMilli: Value(onHandMilli),
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 21),
    );
  }

  PendingSalesCompanion pendingSale(String operationId) {
    final now = DateTime.utc(2026, 9, 21);
    return PendingSalesCompanion.insert(
      clientOperationId: operationId,
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      payloadJson: '{}',
      createdAt: now,
      updatedAt: now,
    );
  }

  test('offline sale is queued and stock is reduced atomically', () async {
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [product(name: 'Maize Meal', sku: 'MM001', onHandMilli: 10000)],
    );

    await database.queueSaleAndApplyStock(
      sale: pendingSale('00000000-0000-4000-8000-000000000001'),
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
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [product(name: 'Sugar', sku: 'SUG001', onHandMilli: 5000)],
    );
    final sale = pendingSale('00000000-0000-4000-8000-000000000002');
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

  test('server catalog refresh preserves deductions from queued offline sales', () async {
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [product(name: 'Bread', sku: 'BR001', onHandMilli: 10000)],
    );
    await database.queueSaleAndApplyStock(
      sale: pendingSale('00000000-0000-4000-8000-000000000003'),
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      stockChanges: const [LocalSaleStockChange(productId: 'product-1', quantityMilli: 2000)],
    );

    // A remote refresh still reports 10 units because this offline sale has not
    // reached the server yet. The projected local stock must remain 8.
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [product(name: 'Bread', sku: 'BR001', onHandMilli: 10000)],
    );

    final products = await database.getProducts(tenantId: 'tenant-1', branchId: 'branch-1');
    expect(products.single.onHandMilli, 8000);
  });

  test('sync conflict releases the rejected local stock deduction', () async {
    await database.replaceProducts(
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      products: [product(name: 'Oil', sku: 'OIL001', onHandMilli: 10000)],
    );
    const operationId = '00000000-0000-4000-8000-000000000004';
    await database.queueSaleAndApplyStock(
      sale: pendingSale(operationId),
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      stockChanges: const [LocalSaleStockChange(productId: 'product-1', quantityMilli: 2000)],
    );

    await database.markPendingSale(
      clientOperationId: operationId,
      status: 'conflict',
      lastError: 'Server rejected sale',
    );

    final products = await database.getProducts(tenantId: 'tenant-1', branchId: 'branch-1');
    expect(products.single.onHandMilli, 10000);
    expect((await database.getPendingSale(operationId))?.status, 'conflict');
  });
}
