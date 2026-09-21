import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class CachedProducts extends Table {
  TextColumn get productId => text()();
  TextColumn get tenantId => text()();
  TextColumn get branchId => text()();
  TextColumn get name => text()();
  TextColumn get sku => text()();
  TextColumn get barcode => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get unit => text().withDefault(const Constant('unit'))();
  IntColumn get sellingPriceMinor => integer()();
  IntColumn get costPriceMinor => integer()();
  IntColumn get onHandMilli => integer().nullable()();
  IntColumn get reorderLevelMilli => integer().withDefault(const Constant(0))();
  BoolColumn get tracksStock => boolean().withDefault(const Constant(true))();
  BoolColumn get isLowStock => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {productId, tenantId, branchId};
}

class PendingSales extends Table {
  TextColumn get clientOperationId => text()();
  TextColumn get tenantId => text()();
  TextColumn get branchId => text()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {clientOperationId};
}

class LocalSaleStockChange {
  const LocalSaleStockChange({required this.productId, required this.quantityMilli});
  final String productId;
  final int quantityMilli;
}

@DriftDatabase(tables: [CachedProducts, PendingSales])
final class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? implementation])
      : super(implementation ?? driftDatabase(name: 'khanya_pos'));

  @override
  int get schemaVersion => 1;

  Stream<List<CachedProduct>> watchProducts({
    required String tenantId,
    required String branchId,
  }) {
    final query = select(cachedProducts)
      ..where((row) => row.tenantId.equals(tenantId) & row.branchId.equals(branchId))
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch();
  }

  Future<List<CachedProduct>> getProducts({
    required String tenantId,
    required String branchId,
  }) {
    return (select(cachedProducts)
          ..where((row) => row.tenantId.equals(tenantId) & row.branchId.equals(branchId))
          ..orderBy([(row) => OrderingTerm.asc(row.name)]))
        .get();
  }

  Future<void> replaceProducts({
    required String tenantId,
    required String branchId,
    required Iterable<CachedProductsCompanion> products,
  }) {
    return transaction(() async {
      await (delete(cachedProducts)
            ..where((row) => row.tenantId.equals(tenantId) & row.branchId.equals(branchId)))
          .go();
      await batch((batch) {
        batch.insertAll(cachedProducts, products, mode: InsertMode.insertOrReplace);
      });
    });
  }

  Future<void> queueSaleAndApplyStock({
    required PendingSalesCompanion sale,
    required String tenantId,
    required String branchId,
    required List<LocalSaleStockChange> stockChanges,
  }) {
    return transaction(() async {
      final operationId = sale.clientOperationId.value;
      final exists = await (select(pendingSales)
            ..where((row) => row.clientOperationId.equals(operationId)))
          .getSingleOrNull();
      if (exists != null) return;

      for (final change in stockChanges) {
        final row = await (select(cachedProducts)
              ..where((product) =>
                  product.productId.equals(change.productId) &
                  product.tenantId.equals(tenantId) &
                  product.branchId.equals(branchId)))
            .getSingleOrNull();
        if (row == null || row.onHandMilli == null || !row.tracksStock) continue;
        final next = row.onHandMilli! - change.quantityMilli;
        if (next < 0) {
          throw StateError('Insufficient cached stock for ${row.name}');
        }
        await (update(cachedProducts)
              ..where((product) =>
                  product.productId.equals(change.productId) &
                  product.tenantId.equals(tenantId) &
                  product.branchId.equals(branchId)))
            .write(CachedProductsCompanion(
          onHandMilli: Value(next),
          isLowStock: Value(next <= row.reorderLevelMilli),
          updatedAt: Value(DateTime.now().toUtc()),
        ));
      }
      await into(pendingSales).insert(sale);
    });
  }

  Stream<int> watchPendingCount() {
    return select(pendingSales).watch().map(
          (rows) => rows.where((row) => row.status != 'synced').length,
        );
  }

  Stream<int> watchConflictCount() {
    return select(pendingSales).watch().map(
          (rows) => rows.where((row) => row.status == 'conflict').length,
        );
  }

  Future<List<PendingSale>> getSyncablePendingSales() {
    return (select(pendingSales)
          ..where((row) => row.status.equals('pending') | row.status.equals('syncing'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  Future<PendingSale?> getPendingSale(String clientOperationId) {
    return (select(pendingSales)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .getSingleOrNull();
  }

  Future<void> markPendingSale({
    required String clientOperationId,
    required String status,
    String? lastError,
    bool incrementAttempts = false,
  }) async {
    final current = await getPendingSale(clientOperationId);
    if (current == null) return;
    await (update(pendingSales)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .write(PendingSalesCompanion(
      status: Value(status),
      attempts: Value(current.attempts + (incrementAttempts ? 1 : 0)),
      lastError: Value(lastError),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<void> deletePendingSale(String clientOperationId) {
    return (delete(pendingSales)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .go();
  }
}
