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

class CachedSuppliers extends Table {
  TextColumn get supplierId => text()();
  TextColumn get tenantId => text()();
  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get taxNumber => text().nullable()();
  IntColumn get outstandingMinor => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {supplierId, tenantId};
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

class PendingDocuments extends Table {
  TextColumn get localDocumentId => text()();
  TextColumn get tenantId => text()();
  TextColumn get branchId => text()();
  TextColumn get documentPurpose => text()();
  TextColumn get localPath => text()();
  TextColumn get filename => text()();
  TextColumn get contentType => text()();
  IntColumn get byteSize => integer()();
  TextColumn get sha256 => text()();
  TextColumn get remoteDocumentId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {localDocumentId};
}

class PendingPurchases extends Table {
  TextColumn get clientOperationId => text()();
  TextColumn get tenantId => text()();
  TextColumn get branchId => text()();
  TextColumn get payloadJson => text()();
  TextColumn get localDocumentId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {clientOperationId};
}

class PendingPurchaseLines extends Table {
  TextColumn get clientOperationId => text()();
  TextColumn get productId => text()();
  IntColumn get quantityMilli => integer()();

  @override
  Set<Column<Object>> get primaryKey => {clientOperationId, productId};
}

class PendingExpenses extends Table {
  TextColumn get clientOperationId => text()();
  TextColumn get tenantId => text()();
  TextColumn get branchId => text()();
  TextColumn get payloadJson => text()();
  TextColumn get localDocumentId => text().nullable()();
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

class LocalPurchaseStockChange {
  const LocalPurchaseStockChange({required this.productId, required this.quantityMilli});
  final String productId;
  final int quantityMilli;
}

@DriftDatabase(
  tables: [
    CachedProducts,
    CachedSuppliers,
    PendingSales,
    PendingSaleLines,
    PendingDocuments,
    PendingPurchases,
    PendingPurchaseLines,
    PendingExpenses,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? implementation])
      : super(implementation ?? driftDatabase(name: 'khanya_pos'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) => migrator.createAll(),
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.createTable(cachedSuppliers);
            await migrator.createTable(pendingDocuments);
            await migrator.createTable(pendingPurchases);
            await migrator.createTable(pendingPurchaseLines);
            await migrator.createTable(pendingExpenses);
          }
        },
      );

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
      await _applyPendingPurchaseAdditions(tenantId: tenantId, branchId: branchId);
      await _applyPendingSaleDeductions(tenantId: tenantId, branchId: branchId);
    });
  }

  Future<void> replaceSuppliers({
    required String tenantId,
    required Iterable<CachedSuppliersCompanion> suppliers,
  }) {
    final rows = suppliers.toList(growable: false);
    return transaction(() async {
      await (delete(cachedSuppliers)..where((row) => row.tenantId.equals(tenantId))).go();
      if (rows.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(cachedSuppliers, rows, mode: InsertMode.insertOrReplace);
        });
      }
    });
  }

  Future<List<CachedSupplier>> getCachedSuppliers(String tenantId) {
    return (select(cachedSuppliers)
          ..where((row) => row.tenantId.equals(tenantId))
          ..orderBy([(row) => OrderingTerm.asc(row.name)]))
        .get();
  }

  Future<void> queueSaleAndApplyStock({
    required PendingSalesCompanion sale,
    required String tenantId,
    required String branchId,
    required List<LocalSaleStockChange> stockChanges,
  }) {
    return transaction(() async {
      final operationId = sale.clientOperationId.value;
      final exists = await getPendingSale(operationId);
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

  Future<void> queuePurchaseAndApplyStock({
    required PendingPurchasesCompanion purchase,
    required String tenantId,
    required String branchId,
    required List<LocalPurchaseStockChange> stockChanges,
  }) {
    return transaction(() async {
      final operationId = purchase.clientOperationId.value;
      final exists = await getPendingPurchase(operationId);
      if (exists != null) return;

      await into(pendingPurchases).insert(purchase);
      for (final change in stockChanges) {
        await into(pendingPurchaseLines).insert(
          PendingPurchaseLinesCompanion.insert(
            clientOperationId: operationId,
            productId: change.productId,
            quantityMilli: change.quantityMilli,
          ),
        );
        final product = await _cachedProduct(
          tenantId: tenantId,
          branchId: branchId,
          productId: change.productId,
        );
        if (product == null || product.onHandMilli == null || !product.tracksStock) continue;
        await _writeProjectedStock(
          row: product,
          onHandMilli: product.onHandMilli! + change.quantityMilli,
        );
      }
    });
  }

  Future<PendingDocument> queueDocument(PendingDocumentsCompanion document) async {
    final existing = await (select(pendingDocuments)
          ..where((row) =>
              row.tenantId.equals(document.tenantId.value) &
              row.sha256.equals(document.sha256.value)))
        .getSingleOrNull();
    if (existing != null) return existing;
    await into(pendingDocuments).insert(document);
    final inserted = await getPendingDocument(document.localDocumentId.value);
    if (inserted == null) throw StateError('Could not persist receipt metadata');
    return inserted;
  }

  Future<void> queueExpense(PendingExpensesCompanion expense) async {
    final exists = await getPendingExpense(expense.clientOperationId.value);
    if (exists == null) await into(pendingExpenses).insert(expense);
  }

  Stream<int> watchPendingCount() {
    return customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM pending_sales WHERE status IN ('pending', 'syncing')) +
        (SELECT COUNT(*) FROM pending_documents WHERE status IN ('pending', 'uploading')) +
        (SELECT COUNT(*) FROM pending_purchases WHERE status IN ('pending', 'syncing')) +
        (SELECT COUNT(*) FROM pending_expenses WHERE status IN ('pending', 'syncing')) AS total
      ''',
      readsFrom: {pendingSales, pendingDocuments, pendingPurchases, pendingExpenses},
    ).watchSingle().map((row) => row.read<int>('total'));
  }

  Stream<int> watchConflictCount() {
    return customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM pending_sales WHERE status = 'conflict') +
        (SELECT COUNT(*) FROM pending_documents WHERE status = 'conflict') +
        (SELECT COUNT(*) FROM pending_purchases WHERE status = 'conflict') +
        (SELECT COUNT(*) FROM pending_expenses WHERE status = 'conflict') AS total
      ''',
      readsFrom: {pendingSales, pendingDocuments, pendingPurchases, pendingExpenses},
    ).watchSingle().map((row) => row.read<int>('total'));
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

  Future<List<PendingDocument>> getSyncablePendingDocuments() {
    return (select(pendingDocuments)
          ..where((row) => row.status.equals('pending') | row.status.equals('uploading'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  Future<List<PendingDocument>> getPendingDocuments({String? tenantId, String? branchId}) {
    final query = select(pendingDocuments);
    if (tenantId != null) query.where((row) => row.tenantId.equals(tenantId));
    if (branchId != null) query.where((row) => row.branchId.equals(branchId));
    query.orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.get();
  }

  Future<PendingDocument?> getPendingDocument(String localDocumentId) {
    return (select(pendingDocuments)
          ..where((row) => row.localDocumentId.equals(localDocumentId)))
        .getSingleOrNull();
  }

  Future<void> markPendingDocument({
    required String localDocumentId,
    required String status,
    String? remoteDocumentId,
    String? lastError,
    bool incrementAttempts = false,
  }) async {
    final current = await getPendingDocument(localDocumentId);
    if (current == null) return;
    await (update(pendingDocuments)
          ..where((row) => row.localDocumentId.equals(localDocumentId)))
        .write(PendingDocumentsCompanion(
      status: Value(status),
      remoteDocumentId: remoteDocumentId == null
          ? Value(current.remoteDocumentId)
          : Value(remoteDocumentId),
      attempts: Value(current.attempts + (incrementAttempts ? 1 : 0)),
      lastError: Value(lastError),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<List<PendingPurchase>> getSyncablePendingPurchases() {
    return (select(pendingPurchases)
          ..where((row) => row.status.equals('pending') | row.status.equals('syncing'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  Future<PendingPurchase?> getPendingPurchase(String clientOperationId) {
    return (select(pendingPurchases)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .getSingleOrNull();
  }

  Future<void> markPendingPurchase({
    required String clientOperationId,
    required String status,
    String? lastError,
    bool incrementAttempts = false,
  }) {
    return transaction(() async {
      final current = await getPendingPurchase(clientOperationId);
      if (current == null) return;
      if (status == 'conflict' && current.status != 'conflict') {
        final lines = await (select(pendingPurchaseLines)
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
            onHandMilli: product.onHandMilli! - line.quantityMilli,
          );
        }
      }
      await (update(pendingPurchases)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .write(PendingPurchasesCompanion(
        status: Value(status),
        attempts: Value(current.attempts + (incrementAttempts ? 1 : 0)),
        lastError: Value(lastError),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
    });
  }

  Future<void> deletePendingPurchase(String clientOperationId) {
    return transaction(() async {
      await (delete(pendingPurchaseLines)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .go();
      await (delete(pendingPurchases)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .go();
    });
  }

  Future<List<PendingExpense>> getSyncablePendingExpenses() {
    return (select(pendingExpenses)
          ..where((row) => row.status.equals('pending') | row.status.equals('syncing'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  Future<PendingExpense?> getPendingExpense(String clientOperationId) {
    return (select(pendingExpenses)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .getSingleOrNull();
  }

  Future<void> markPendingExpense({
    required String clientOperationId,
    required String status,
    String? lastError,
    bool incrementAttempts = false,
  }) async {
    final current = await getPendingExpense(clientOperationId);
    if (current == null) return;
    await (update(pendingExpenses)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .write(PendingExpensesCompanion(
      status: Value(status),
      attempts: Value(current.attempts + (incrementAttempts ? 1 : 0)),
      lastError: Value(lastError),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<void> deletePendingExpense(String clientOperationId) {
    return (delete(pendingExpenses)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .go();
  }

  Future<String?> deletePendingDocumentIfUnreferenced(String localDocumentId) {
    return transaction(() async {
      final purchase = await (select(pendingPurchases)
            ..where((row) => row.localDocumentId.equals(localDocumentId)))
          .getSingleOrNull();
      final expense = await (select(pendingExpenses)
            ..where((row) => row.localDocumentId.equals(localDocumentId)))
          .getSingleOrNull();
      if (purchase != null || expense != null) return null;
      final document = await getPendingDocument(localDocumentId);
      if (document == null) return null;
      await (delete(pendingDocuments)
            ..where((row) => row.localDocumentId.equals(localDocumentId)))
          .go();
      return document.localPath;
    });
  }

  Future<void> _applyPendingPurchaseAdditions({
    required String tenantId,
    required String branchId,
  }) async {
    final active = await (select(pendingPurchases)
          ..where((row) =>
              row.tenantId.equals(tenantId) &
              row.branchId.equals(branchId) &
              (row.status.equals('pending') | row.status.equals('syncing'))))
        .get();
    if (active.isEmpty) return;
    final operationIds = active.map((purchase) => purchase.clientOperationId).toList(growable: false);
    final lines = await (select(pendingPurchaseLines)
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
        onHandMilli: product.onHandMilli! + entry.value,
      );
    }
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
