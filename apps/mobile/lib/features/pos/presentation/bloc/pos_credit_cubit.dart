import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';

class PosCreditState extends Equatable {
  const PosCreditState({this.customer, this.immediatePaymentMinor});

  final CustomerSummary? customer;

  /// Null means pay the full cart total now. Zero means full credit.
  /// A positive value lower than the cart total means partial payment.
  final int? immediatePaymentMinor;

  int paidMinorFor(int totalMinor) {
    final configured = immediatePaymentMinor;
    if (configured == null) return totalMinor;
    return configured.clamp(0, totalMinor);
  }

  int creditMinorFor(int totalMinor) => totalMinor - paidMinorFor(totalMinor);

  bool canSubmit(int totalMinor) {
    final credit = creditMinorFor(totalMinor);
    if (credit <= 0) return true;
    return customer?.canCoverCredit(credit) ?? false;
  }

  @override
  List<Object?> get props => [customer, immediatePaymentMinor];
}

class PosCreditCubit extends Cubit<PosCreditState> {
  PosCreditCubit() : super(const PosCreditState());

  void selectCustomer(CustomerSummary customer) {
    emit(PosCreditState(
      customer: customer,
      immediatePaymentMinor: state.immediatePaymentMinor,
    ));
  }

  void clearCustomer() {
    emit(const PosCreditState());
  }

  void payFull() {
    emit(PosCreditState(customer: state.customer));
  }

  void payOnCredit() {
    if (state.customer == null) return;
    emit(PosCreditState(customer: state.customer, immediatePaymentMinor: 0));
  }

  void setPartialPayment(int amountMinor) {
    if (state.customer == null || amountMinor < 0) return;
    emit(PosCreditState(
      customer: state.customer,
      immediatePaymentMinor: amountMinor,
    ));
  }

  void reset() {
    emit(const PosCreditState());
  }
}
