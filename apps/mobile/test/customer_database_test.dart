import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/customers/data/customer_database.dart';

void main() {
  late CustomerDatabase database;

  setUp(() {
    database = CustomerDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  CachedCustomersCompanion customer({
    int outstandingMinor = 2000,
    int availableCreditMinor = 8000,
  }) {
    return CachedCustomersCompanion.insert(
      customerId: 'customer-1',
      tenantId: 'tenant-1',
      code: 'CUS-001',
      name: 'Mpho Traders',
      creditLimitMinor: const Value(10000),
      paymentTermsDays: const Value(30),
      outstandingMinor: Value(outstandingMinor),
      availableCreditMinor: Value(availableCreditMinor),
      updatedAt: DateTime.utc(2026, 9, 21),
    );
  }

  test('offline credit reservation reduces available credit and survives remote refresh', () async {
    await database.replaceCustomers(tenantId: 'tenant-1', customers: [customer()]);

    await database.reserveCredit(
      clientOperationId: 'sale-1',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      customerId: 'customer-1',
      creditMinor: 3000,
    );

    var projected = await database.getCustomer(
      tenantId: 'tenant-1',
      customerId: 'customer-1',
    );
    expect(projected!.outstandingMinor, 5000);
    expect(projected.availableCreditMinor, 5000);

    // Server still reports the old balance because the offline sale is not synced yet.
    await database.replaceCustomers(tenantId: 'tenant-1', customers: [customer()]);

    projected = await database.getCustomer(
      tenantId: 'tenant-1',
      customerId: 'customer-1',
    );
    expect(projected!.outstandingMinor, 5000);
    expect(projected.availableCreditMinor, 5000);
  });

  test('offline credit reservation cannot exceed projected available credit', () async {
    await database.replaceCustomers(tenantId: 'tenant-1', customers: [customer()]);

    await database.reserveCredit(
      clientOperationId: 'sale-1',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      customerId: 'customer-1',
      creditMinor: 5000,
    );

    expect(
      () => database.reserveCredit(
        clientOperationId: 'sale-2',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        customerId: 'customer-1',
        creditMinor: 4000,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('rejected sale releases its local credit reservation', () async {
    await database.replaceCustomers(tenantId: 'tenant-1', customers: [customer()]);
    await database.reserveCredit(
      clientOperationId: 'sale-1',
      tenantId: 'tenant-1',
      branchId: 'branch-1',
      customerId: 'customer-1',
      creditMinor: 3000,
    );

    await database.releaseCreditReservation('sale-1');

    final projected = await database.getCustomer(
      tenantId: 'tenant-1',
      customerId: 'customer-1',
    );
    expect(projected!.outstandingMinor, 2000);
    expect(projected.availableCreditMinor, 8000);
  });

  test('queued customer payment projects receivable reduction and conflict rolls it back', () async {
    await database.replaceCustomers(tenantId: 'tenant-1', customers: [customer()]);
    final now = DateTime.utc(2026, 9, 21, 12);

    await database.queuePayment(
      payment: PendingCustomerPaymentsCompanion.insert(
        clientOperationId: 'payment-1',
        tenantId: 'tenant-1',
        branchId: 'branch-1',
        customerId: 'customer-1',
        payloadJson: '{}',
        amountMinor: 2500,
        createdAt: now,
        updatedAt: now,
      ),
    );

    var projected = await database.getCustomer(
      tenantId: 'tenant-1',
      customerId: 'customer-1',
    );
    expect(projected!.outstandingMinor, 0);
    expect(projected.availableCreditMinor, 10000);

    await database.markPendingPayment(
      clientOperationId: 'payment-1',
      status: 'conflict',
      lastError: 'Rejected by server',
    );

    projected = await database.getCustomer(
      tenantId: 'tenant-1',
      customerId: 'customer-1',
    );
    expect(projected!.outstandingMinor, 2000);
    expect(projected.availableCreditMinor, 8000);
    expect((await database.getPendingPayment('payment-1'))?.status, 'conflict');
  });
}
