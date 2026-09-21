import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/pos_credit_cubit.dart';

void main() {
  const customer = CustomerSummary(
    id: 'customer-1',
    code: 'CUS-001',
    name: 'Mpho Traders',
    creditLimitMinor: 10000,
    paymentTermsDays: 30,
    outstandingMinor: 2000,
    availableCreditMinor: 8000,
    isActive: true,
  );

  test('walk-in checkout defaults to full immediate payment', () async {
    final cubit = PosCreditCubit();
    addTearDown(cubit.close);

    expect(cubit.state.paidMinorFor(5000), 5000);
    expect(cubit.state.creditMinorFor(5000), 0);
    expect(cubit.state.canSubmit(5000), isTrue);
  });

  test('selected customer can move from full payment to part payment and full credit', () async {
    final cubit = PosCreditCubit();
    addTearDown(cubit.close);

    cubit.selectCustomer(customer);
    cubit.setPartialPayment(3000);
    expect(cubit.state.paidMinorFor(7000), 3000);
    expect(cubit.state.creditMinorFor(7000), 4000);
    expect(cubit.state.canSubmit(7000), isTrue);

    cubit.payOnCredit();
    expect(cubit.state.paidMinorFor(7000), 0);
    expect(cubit.state.creditMinorFor(7000), 7000);
    expect(cubit.state.canSubmit(7000), isTrue);

    cubit.payFull();
    expect(cubit.state.paidMinorFor(7000), 7000);
    expect(cubit.state.creditMinorFor(7000), 0);
  });

  test('credit plan is blocked when requested debt exceeds available credit', () async {
    final cubit = PosCreditCubit();
    addTearDown(cubit.close);

    cubit.selectCustomer(customer);
    cubit.payOnCredit();

    expect(cubit.state.creditMinorFor(9000), 9000);
    expect(cubit.state.canSubmit(9000), isFalse);
  });

  test('clearing customer also clears a prior credit plan', () async {
    final cubit = PosCreditCubit();
    addTearDown(cubit.close);

    cubit.selectCustomer(customer);
    cubit.payOnCredit();
    cubit.clearCustomer();

    expect(cubit.state.customer, isNull);
    expect(cubit.state.paidMinorFor(5000), 5000);
    expect(cubit.state.creditMinorFor(5000), 0);
  });
}
