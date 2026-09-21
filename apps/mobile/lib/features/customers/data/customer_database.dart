import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'customer_database.g.dart';

class CachedCustomers extends Table {
  TextColumn get customerId => text()();
  TextColumn get tenantId => text()();
  TextColumn get code => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  IntColumn get creditLimitMinor => integer().withDefault(const Constant(0))();
  IntColumn get paymentTermsDays => integer().withDefault(const Constant(0))();
  IntColumn get outstandingMinor => integer().withDefault(const Constant(0))();
  IntColumn get availableCreditMinor => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {customerId, tenantId};
}

class PendingCustomerPayments extends Table {
  TextColumn get clientOperationId => text()();
  TextColumn get tenantId => text()();
  TextColumn get branchId => text()();
  TextColumn get customerId => text()();
  TextColumn get payloadJson => text()();
  IntColumn get amountMinor => integer()();
  IntColumn get projectedAppliedMinor => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {clientOperationId};
}

class PendingCustomerCredits extends Table {
  TextColumn get clientOperationId => text()();
  TextColumn get tenantId => text()();
  TextColumn get branchId => text()();
  TextColumn get customerId => text()();
  IntColumn get creditMinor => integer()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {clientOperationId};
}

@DriftDatabase(
  tables: [
    CachedCustomers,
    PendingCustomerPayments,
    PendingCustomerCredits,
  ],
)
final class CustomerDatabase extends _$CustomerDatabase {
  CustomerDatabase([QueryExecutor? implementation])
      : super(implementation ?? driftDatabase(name: 'khanya_customers'));

  @override
  int get schemaVersion => 1;

  Stream<List<CachedCustomer>> watchCustomers(String tenantId) {
    final query = select(cachedCustomers)
      ..where((row) => row.tenantId.equals(tenantId) & row.isActive.equals(true))
      ..orderBy([(row) => OrderingTerm.asc(row.name)]);
    return query.watch();
  }

  Future<List<CachedCustomer>> getCustomers(String tenantId) {
    return (select(cachedCustomers)
          ..where((row) => row.tenantId.equals(tenantId) & row.isActive.equals(true))
          ..orderBy([(row) => OrderingTerm.asc(row.name)]))
        .get();
  }

  Future<CachedCustomer?> getCustomer({
    required String tenantId,
    required String customerId,
  }) {
    return (select(cachedCustomers)
          ..where((row) =>
              row.tenantId.equals(tenantId) & row.customerId.equals(customerId)))
        .getSingleOrNull();
  }

  Future<void> replaceCustomers({
    required String tenantId,
    required Iterable<CachedCustomersCompanion> customers,
  }) {
    final rows = customers.toList(growable: false);
    return transaction(() async {
      await (delete(cachedCustomers)..where((row) => row.tenantId.equals(tenantId))).go();
      if (rows.isNotEmpty) {
        await batch((batch) {
          batch.insertAll(cachedCustomers, rows, mode: InsertMode.insertOrReplace);
        });
      }
      await _reapplyCreditReservations(tenantId);
      await _reapplyPendingPayments(tenantId);
    });
  }

  Future<void> reserveCredit({
    required String clientOperationId,
    required String tenantId,
    required String branchId,
    required String customerId,
    required int creditMinor,
  }) {
    if (creditMinor <= 0) return Future<void>.value();
    return transaction(() async {
      final existing = await (select(pendingCustomerCredits)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .getSingleOrNull();
      if (existing != null) return;

      final customer = await getCustomer(tenantId: tenantId, customerId: customerId);
      if (customer == null || !customer.isActive) {
        throw StateError('Customer is not available for credit on this device.');
      }
      if (creditMinor > customer.availableCreditMinor) {
        throw StateError(
          'Credit limit exceeded. Available credit is ${customer.availableCreditMinor} minor units.',
        );
      }

      await into(pendingCustomerCredits).insert(
        PendingCustomerCreditsCompanion.insert(
          clientOperationId: clientOperationId,
          tenantId: tenantId,
          branchId: branchId,
          customerId: customerId,
          creditMinor: creditMinor,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await _applyCredit(customer, creditMinor);
    });
  }

  Future<void> releaseCreditReservation(String clientOperationId) {
    return transaction(() async {
      final reservation = await (select(pendingCustomerCredits)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .getSingleOrNull();
      if (reservation == null) return;
      final customer = await getCustomer(
        tenantId: reservation.tenantId,
        customerId: reservation.customerId,
      );
      if (customer != null) {
        final nextOutstanding = _maxInt(0, customer.outstandingMinor - reservation.creditMinor);
        final nextAvailable = _minInt(
          customer.creditLimitMinor,
          customer.availableCreditMinor + reservation.creditMinor,
        );
        await _writeProjection(
          customer,
          outstandingMinor: nextOutstanding,
          availableCreditMinor: nextAvailable,
        );
      }
      await (delete(pendingCustomerCredits)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .go();
    });
  }

  Future<void> finalizeCreditReservation(String clientOperationId) {
    return (delete(pendingCustomerCredits)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .go();
  }

  Future<void> reconcileCreditReservations({
    required String tenantId,
    required Set<String> activeSaleOperationIds,
  }) async {
    final reservations = await (select(pendingCustomerCredits)
          ..where((row) => row.tenantId.equals(tenantId)))
        .get();
    for (final reservation in reservations) {
      if (!activeSaleOperationIds.contains(reservation.clientOperationId)) {
        await releaseCreditReservation(reservation.clientOperationId);
      }
    }
  }

  Future<void> queuePayment({
    required PendingCustomerPaymentsCompanion payment,
  }) {
    return transaction(() async {
      final operationId = payment.clientOperationId.value;
      final existing = await getPendingPayment(operationId);
      if (existing != null) return;

      final customer = await getCustomer(
        tenantId: payment.tenantId.value,
        customerId: payment.customerId.value,
      );
      if (customer == null || !customer.isActive) {
        throw StateError('Customer is not available on this device.');
      }
      final amountMinor = payment.amountMinor.value;
      if (amountMinor <= 0) throw StateError('Payment amount must be greater than zero.');
      final applied = _minInt(amountMinor, customer.outstandingMinor);

      await into(pendingCustomerPayments).insert(
        payment.copyWith(projectedAppliedMinor: Value(applied)),
      );
      await _applyPayment(customer, applied);
    });
  }

  Future<List<PendingCustomerPayment>> getSyncablePendingPayments() {
    return (select(pendingCustomerPayments)
          ..where((row) => row.status.equals('pending') | row.status.equals('syncing'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  Future<PendingCustomerPayment?> getPendingPayment(String clientOperationId) {
    return (select(pendingCustomerPayments)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .getSingleOrNull();
  }

  Future<void> markPendingPayment({
    required String clientOperationId,
    required String status,
    String? lastError,
    bool incrementAttempts = false,
  }) {
    return transaction(() async {
      final current = await getPendingPayment(clientOperationId);
      if (current == null) return;

      if (status == 'conflict' && current.status != 'conflict') {
        final customer = await getCustomer(
          tenantId: current.tenantId,
          customerId: current.customerId,
        );
        if (customer != null) {
          final applied = current.projectedAppliedMinor;
          await _writeProjection(
            customer,
            outstandingMinor: customer.outstandingMinor + applied,
            availableCreditMinor: _maxInt(0, customer.availableCreditMinor - applied),
          );
        }
      }

      await (update(pendingCustomerPayments)
            ..where((row) => row.clientOperationId.equals(clientOperationId)))
          .write(
        PendingCustomerPaymentsCompanion(
          status: Value(status),
          attempts: Value(current.attempts + (incrementAttempts ? 1 : 0)),
          lastError: Value(lastError),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  Future<void> deletePendingPayment(String clientOperationId) {
    return (delete(pendingCustomerPayments)
          ..where((row) => row.clientOperationId.equals(clientOperationId)))
        .go();
  }

  Stream<int> watchPendingCount() {
    final count = pendingCustomerPayments.clientOperationId.count();
    return (selectOnly(pendingCustomerPayments)
          ..addColumns([count])
          ..where(pendingCustomerPayments.status.equals('pending') |
              pendingCustomerPayments.status.equals('syncing')))
        .watchSingle()
        .map((row) => row.read(count) ?? 0);
  }

  Stream<int> watchConflictCount() {
    final count = pendingCustomerPayments.clientOperationId.count();
    return (selectOnly(pendingCustomerPayments)
          ..addColumns([count])
          ..where(pendingCustomerPayments.status.equals('conflict')))
        .watchSingle()
        .map((row) => row.read(count) ?? 0);
  }

  Future<void> _reapplyCreditReservations(String tenantId) async {
    final reservations = await (select(pendingCustomerCredits)
          ..where((row) => row.tenantId.equals(tenantId))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
    for (final reservation in reservations) {
      final customer = await getCustomer(tenantId: tenantId, customerId: reservation.customerId);
      if (customer != null) await _applyCredit(customer, reservation.creditMinor);
    }
  }

  Future<void> _reapplyPendingPayments(String tenantId) async {
    final payments = await (select(pendingCustomerPayments)
          ..where((row) =>
              row.tenantId.equals(tenantId) &
              (row.status.equals('pending') | row.status.equals('syncing')))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
    for (final payment in payments) {
      final customer = await getCustomer(tenantId: tenantId, customerId: payment.customerId);
      if (customer == null) continue;
      final applied = _minInt(payment.amountMinor, customer.outstandingMinor);
      await (update(pendingCustomerPayments)
            ..where((row) => row.clientOperationId.equals(payment.clientOperationId)))
          .write(PendingCustomerPaymentsCompanion(projectedAppliedMinor: Value(applied)));
      await _applyPayment(customer, applied);
    }
  }

  Future<void> _applyCredit(CachedCustomer customer, int creditMinor) {
    return _writeProjection(
      customer,
      outstandingMinor: customer.outstandingMinor + creditMinor,
      availableCreditMinor: _maxInt(0, customer.availableCreditMinor - creditMinor),
    );
  }

  Future<void> _applyPayment(CachedCustomer customer, int appliedMinor) {
    return _writeProjection(
      customer,
      outstandingMinor: _maxInt(0, customer.outstandingMinor - appliedMinor),
      availableCreditMinor: _minInt(
        customer.creditLimitMinor,
        customer.availableCreditMinor + appliedMinor,
      ),
    );
  }

  Future<void> _writeProjection(
    CachedCustomer customer, {
    required int outstandingMinor,
    required int availableCreditMinor,
  }) {
    return (update(cachedCustomers)
          ..where((row) =>
              row.tenantId.equals(customer.tenantId) &
              row.customerId.equals(customer.customerId)))
        .write(
      CachedCustomersCompanion(
        outstandingMinor: Value(outstandingMinor),
        availableCreditMinor: Value(availableCreditMinor),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}

int _minInt(int a, int b) => a < b ? a : b;
int _maxInt(int a, int b) => a > b ? a : b;
