import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';

class PosCreditState extends Equatable {
  const PosCreditState({
    this.customer,
    this.immediatePaymentMinor,
    this.checkoutTotalOverrideMinor,
  });

  final CustomerSummary? customer;

  /// Null means pay the full cart total now. Zero means full credit.
  /// A positive value lower than the cart total means partial payment.
  final int? immediatePaymentMinor;

  /// A promotion/loyalty-adjusted total. Methods receive the gross cart total
  /// and transparently use this lower total while it remains applicable.
  final int? checkoutTotalOverrideMinor;

  int effectiveTotalFor(int grossTotalMinor) {
    final override = checkoutTotalOverrideMinor;
    if (override == null) return grossTotalMinor;
    return math.min(grossTotalMinor, math.max(0, override));
  }

  int paidMinorFor(int grossTotalMinor) {
    final totalMinor = effectiveTotalFor(grossTotalMinor);
    final configured = immediatePaymentMinor;
    if (configured == null) return totalMinor;
    return configured.clamp(0, totalMinor).toInt();
  }

  int creditMinorFor(int grossTotalMinor) {
    final totalMinor = effectiveTotalFor(grossTotalMinor);
    return totalMinor - paidMinorFor(grossTotalMinor);
  }

  bool canSubmit(int grossTotalMinor) {
    final credit = creditMinorFor(grossTotalMinor);
    if (credit <= 0) return true;
    return customer?.canCoverCredit(credit) ?? false;
  }

  @override
  List<Object?> get props => [customer, immediatePaymentMinor, checkoutTotalOverrideMinor];
}

class PosCreditCubit extends Cubit<PosCreditState> {
  PosCreditCubit() : super(const PosCreditState());

  void selectCustomer(CustomerSummary customer) {
    emit(PosCreditState(
      customer: customer,
      immediatePaymentMinor: state.immediatePaymentMinor,
      checkoutTotalOverrideMinor: state.checkoutTotalOverrideMinor,
    ));
  }

  void clearCustomer() {
    emit(PosCreditState(checkoutTotalOverrideMinor: state.checkoutTotalOverrideMinor));
  }

  void payFull() {
    emit(PosCreditState(
      customer: state.customer,
      checkoutTotalOverrideMinor: state.checkoutTotalOverrideMinor,
    ));
  }

  void payOnCredit() {
    if (state.customer == null) return;
    emit(PosCreditState(
      customer: state.customer,
      immediatePaymentMinor: 0,
      checkoutTotalOverrideMinor: state.checkoutTotalOverrideMinor,
    ));
  }

  void setPartialPayment(int amountMinor) {
    if (state.customer == null || amountMinor < 0) return;
    emit(PosCreditState(
      customer: state.customer,
      immediatePaymentMinor: amountMinor,
      checkoutTotalOverrideMinor: state.checkoutTotalOverrideMinor,
    ));
  }

  void setCheckoutTotalOverride(int? totalMinor) {
    emit(PosCreditState(
      customer: state.customer,
      immediatePaymentMinor: state.immediatePaymentMinor,
      checkoutTotalOverrideMinor: totalMinor,
    ));
  }

  void reset() {
    emit(const PosCreditState());
  }
}
