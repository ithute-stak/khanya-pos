import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/pos/domain/mobile_money_provider.dart';

void main() {
  const request = MobileMoneyCollectionRequest(
    operationId: 'op-0001',
    tenantId: 'merchant-a',
    branchId: 'branch-1',
    amountMinor: 12500,
    currency: 'LSL',
    rail: MobileMoneyRail.mpesa,
  );

  MobileMoneyCollectionStatusSnapshot snapshot({
    MobileMoneyCollectionStatus status = MobileMoneyCollectionStatus.confirmed,
    String operationId = 'op-0001',
    String tenantId = 'merchant-a',
    String branchId = 'branch-1',
    int amountMinor = 12500,
    String currency = 'LSL',
    MobileMoneyRail rail = MobileMoneyRail.mpesa,
    String? reference = 'provider-ref-123',
  }) =>
      MobileMoneyCollectionStatusSnapshot(
        operationId: operationId,
        tenantId: tenantId,
        branchId: branchId,
        amountMinor: amountMinor,
        currency: currency,
        rail: rail,
        status: status,
        providerReference: reference,
      );

  test('validates a positive LSL amount and all merchant bindings', () {
    expect(request.validate, returnsNormally);
    expect(
      () => const MobileMoneyCollectionRequest(
        operationId: 'op-0002',
        tenantId: 'merchant-a',
        branchId: 'branch-1',
        amountMinor: 0,
        currency: 'LSL',
        rail: MobileMoneyRail.ecocash,
      ).validate(),
      throwsArgumentError,
    );
    expect(
      () => const MobileMoneyCollectionRequest(
        operationId: 'op-0002',
        tenantId: '',
        branchId: 'branch-1',
        amountMinor: 100,
        currency: 'LSL',
        rail: MobileMoneyRail.ecocash,
      ).validate(),
      throwsArgumentError,
    );
  });

  test('only exact same merchant, branch, operation and amount may match', () {
    expect(snapshot().matches(request), isTrue);
    expect(snapshot(operationId: 'other').matches(request), isFalse);
    expect(snapshot(tenantId: 'merchant-b').matches(request), isFalse);
    expect(snapshot(branchId: 'branch-2').matches(request), isFalse);
    expect(snapshot(amountMinor: 12501).matches(request), isFalse);
    expect(snapshot(currency: 'USD').matches(request), isFalse);
    expect(snapshot(rail: MobileMoneyRail.ecocash).matches(request), isFalse);
  });

  test('pending and unknown states never appear confirmed', () {
    for (final status in [
      MobileMoneyCollectionStatus.awaitingCustomer,
      MobileMoneyCollectionStatus.pendingProvider,
      MobileMoneyCollectionStatus.failed,
      MobileMoneyCollectionStatus.cancelled,
      MobileMoneyCollectionStatus.unknown,
    ]) {
      expect(snapshot(status: status).confirmedForDisplay(request), isFalse);
    }
  });

  test('confirmed display needs exact binding and provider reference', () {
    expect(snapshot().confirmedForDisplay(request), isTrue);
    expect(snapshot(reference: ' ').confirmedForDisplay(request), isFalse);
    expect(snapshot(reference: null).confirmedForDisplay(request), isFalse);
    expect(snapshot(amountMinor: 10000).confirmedForDisplay(request), isFalse);
  });
}
