import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';
import 'package:khanya_pos/features/pos/domain/checkout_benefits.dart';

class PosCreditState extends Equatable {
  const PosCreditState({this.customer, this.immediatePaymentMinor, this.benefitsRevision = 0});

  final CustomerSummary? customer;

  /// Null means pay the full effective sale total now. Zero means full credit.
  /// A positive value lower than the effective sale total means partial payment.
  final int? immediatePaymentMinor;

  /// Changes whenever a validated promotion/loyalty preview is applied so the
  /// panel rebuilds even though the selection itself lives in the shared store.
  final int benefitsRevision;

  int effectiveTotalMinorFor(int subtotalMinor) {
    final selection = CheckoutBenefitsStore.validFor(
      subtotalMinor: subtotalMinor,
      customerId: customer?.id,
    );
    return selection?.totalMinor ?? subtotalMinor;
  }

  int discountMinorFor(int subtotalMinor) {
    final selection = CheckoutBenefitsStore.validFor(
      subtotalMinor: subtotalMinor,
      customerId: customer?.id,
    );
    return selection?.discountMinor ?? 0;
  }

  int paidMinorFor(int subtotalMinor) {
    final totalMinor = effectiveTotalMinorFor(subtotalMinor);
    final configured = immediatePaymentMinor;
    if (configured == null) return totalMinor;
    return configured.clamp(0, totalMinor).toInt();
  }

  int creditMinorFor(int subtotalMinor) => effectiveTotalMinorFor(subtotalMinor) - paidMinorFor(subtotalMinor);

  bool canSubmit(int subtotalMinor) {
    final credit = creditMinorFor(subtotalMinor);
    if (credit <= 0) return true;
    return customer?.canCoverCredit(credit) ?? false;
  }

  @override
  List<Object?> get props => [customer, immediatePaymentMinor, benefitsRevision];
}

class PosCreditCubit extends Cubit<PosCreditState> {
  PosCreditCubit() : super(const PosCreditState());

  void selectCustomer(CustomerSummary customer) {
    if (state.customer?.id != customer.id) CheckoutBenefitsStore.clear();
    emit(PosCreditState(
      customer: customer,
      immediatePaymentMinor: state.immediatePaymentMinor,
      benefitsRevision: state.benefitsRevision + 1,
    ));
  }

  void clearCustomer() {
    CheckoutBenefitsStore.clear();
    emit(PosCreditState(benefitsRevision: state.benefitsRevision + 1));
  }

  void payFull() {
    emit(PosCreditState(
      customer: state.customer,
      benefitsRevision: state.benefitsRevision,
    ));
  }

  void payOnCredit() {
    if (state.customer == null) return;
    emit(PosCreditState(
      customer: state.customer,
      immediatePaymentMinor: 0,
      benefitsRevision: state.benefitsRevision,
    ));
  }

  void setPartialPayment(int amountMinor) {
    if (state.customer == null || amountMinor < 0) return;
    emit(PosCreditState(
      customer: state.customer,
      immediatePaymentMinor: amountMinor,
      benefitsRevision: state.benefitsRevision,
    ));
  }

  void benefitsUpdated() {
    emit(PosCreditState(
      customer: state.customer,
      immediatePaymentMinor: state.immediatePaymentMinor,
      benefitsRevision: state.benefitsRevision + 1,
    ));
  }

  void reset() {
    CheckoutBenefitsStore.clear();
    emit(PosCreditState(benefitsRevision: state.benefitsRevision + 1));
  }
}
