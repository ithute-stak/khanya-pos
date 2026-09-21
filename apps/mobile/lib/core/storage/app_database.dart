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

class PendingSaleLines extends Table {
  TextColumn get clientOperationId => text()();
  TextColumn get productId => text()();
  IntColumn get quantityMilli => integer()();

  @override
  Set<Column<Object>> get primaryKey => {clientOperationId, productId};
}

class LocalSaleStockChange {
  const LocalSaleStockChange({required this.productId, required this.quantityMilli});
  final String productId;
  final int quantityMilli;
}

@DriftDatabase(tables: [CachedProducts, PendingSales, PendingSaleLines])
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
    final replacementRows = products.toList(growable: false);
    return transaction(() async {
      await (delete(cachedProducts)
            ..where((row) => row.tenantId.equals(tenantId) & row.branchId.equals(branchId)))
          .go();
      if (replacementRows.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(cachedProducts, replacementRows, mode: InsertMode.insertOrReplace);
        });
      }
      await _applyPendingSaleDeductions(tenantId: tenantId, branchId: branchId);
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

      await into(pendingSales).insert(sale);
      for (final change in stockChanges) {
        await into(pendingSaleLines).insert(
          PendingSaleLinesCompanion.insert(
            clientOperationId: operationId,
            productId: change.productId,
            quantityMilli: change.quantityMilli,
          ),
        );

        final row = await _cachedProduct(
          tenantId: tenantId,
          branchId: branchId,
          productId: change.productId,
        );
        if (row == null || row.onHandMilli == null || !row.tracksStock) continue;
        final next = row.onHandMilli! - change.quantityMilli;
        if (next < 0) {
          throw StateError('Insufficient cached stock for ${row.name}');
        }
        await _writeProjectedStock(row: row, onHandMilli: next);
      }
    });
  }

  Stream<int> watchPendingCount() {
    final query = select(pendingSales)
      ..where((row) => row.status.equals('pending') | row.status.equals('syncing'));
    return query.watch().map((rows) => rows.length);
  }

  Stream<int> watchConflictCount() {
    final query = select(pendingSales)..where((row) => row.status.equals('conflict'));
    return query.watch().map((rows) => rows.length);
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
  }) {
    return transaction(() async {
      final current = await getPendingSale(clientOperationId);
      if (current == null) return;

      if (status == 'conflict' && current.status != 'conflict') {
        final lines = await (select(pendingSaleLines)
              ..where((row) => row.clientOperationId.equals(clientOperationId)))
            .get();
        for (final line in lines) {
          final product = await _cachedProduct(
            tenantId: current.tenantId,
            branchId: current.branchId,
            productId: line.productId,
          );
          if (product == null || product.onHandMilli == null || !product.tracksStock) continue;
          await _writeProjectedStock(
            row: product,
            onHandMilli: product.onHandMilli! + line.quantityMilli,
          );
        }
      }

      await (update(pendingSales)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .write(PendingSalesCompanion(
        status: Value(status),
        attempts: Value(current.attempts + (incrementAttempts ? 1 : 0)),
        lastError: Value(lastError),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    });
  }

  Future<void> deletePendingSale(String clientOperationId) {
    return transaction(() async {
      await (delete(pendingSaleLines)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .go();
      await (delete(pendingSales)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .go();
    });
  }

  Future<void> _applyPendingSaleDeductions({
    required String tenantId,
    required String branchId,
  }) async {
    final activeSales = await (select(pendingSales)
          ..where((row) =>
              row.tenantId.equals(tenantId) &
              row.branchId.equals(branchId) &
              (row.status.equals('pending') | row.status.equals('syncing'))))
        .get();
    if (activeSales.isEmpty) return;

    final operationIds = activeSales.map((sale) => sale.clientOperationId).toList(growable: false);
    final lines = await (select(pendingSaleLines)
          ..where((row) => row.clientOperationId.isIn(operationIds)))
        .get();
    final quantityByProduct = <String, int>{};
    for (final line in lines) {
      quantityByProduct.update(
        line.productId,
        (quantity) => quantity + line.quantityMilli,
        ifAbsent: () => line.quantityMilli,
      );
    }

    for (final entry in quantityByProduct.entries) {
      final product = await _cachedProduct(
        tenantId: tenantId,
        branchId: branchId,
        productId: entry.key,
      );
      if (product == null || product.onHandMilli == null || !product.tracksStock) continue;
      await _writeProjectedStock(
        row: product,
        onHandMilli: product.onHandMilli! - entry.value,
      );
    }
  }

  Future<CachedProduct?> _cachedProduct({
    required String tenantId,
    required String branchId,
    required String productId,
  }) {
    return (select(cachedProducts)
          ..where((product) =>
              product.productId.equals(productId) &
              product.tenantId.equals(tenantId) &
              product.branchId.equals(branchId)))
        .getSingleOrNull();
  }

  Future<void> _writeProjectedStock({
    required CachedProduct row,
    required int onHandMilli,
  }) {
    return (update(cachedProducts)
          ..where((product) =>
              product.productId.equals(row.productId) &
              product.tenantId.equals(row.tenantId) &
              product.branchId.equals(row.branchId)))
        .write(CachedProductsCompanion(
      onHandMilli: Value(onHandMilli),
      isLowStock: Value(onHandMilli <= row.reorderLevelMilli),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }
}
