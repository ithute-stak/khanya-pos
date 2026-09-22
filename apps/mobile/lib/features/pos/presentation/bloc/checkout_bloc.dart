import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';
import 'package:khanya_pos/features/pos/data/sales_repository.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';

sealed class CheckoutEvent extends Equatable {
  const CheckoutEvent();
  @override
  List<Object?> get props => [];
}

final class CheckoutSaleRequested extends CheckoutEvent {
  const CheckoutSaleRequested({
    required this.lines,
    required this.paymentMethod,
    this.customer,
    this.immediatePaymentMinor,
    this.cashTenderedMinor,
  });

  final List<CartLine> lines;
  final PaymentMethod paymentMethod;
  final CustomerSummary? customer;
  final int? immediatePaymentMinor;
  final int? cashTenderedMinor;

  @override
  List<Object?> get props => [
        lines,
        paymentMethod,
        customer,
        immediatePaymentMinor,
        cashTenderedMinor,
      ];
}

final class CheckoutReset extends CheckoutEvent {
  const CheckoutReset();
}

enum CheckoutStatus { idle, submitting, completed, failed }

class CheckoutState extends Equatable {
  const CheckoutState({
    this.status = CheckoutStatus.idle,
    this.submission,
    this.errorMessage,
    this.lines = const [],
    this.paymentMethod,
    this.customer,
    this.immediatePaymentMinor,
    this.cashTenderedMinor,
  });

  final CheckoutStatus status;
  final SaleSubmission? submission;
  final String? errorMessage;
  final List<CartLine> lines;
  final PaymentMethod? paymentMethod;
  final CustomerSummary? customer;
  final int? immediatePaymentMinor;
  final int? cashTenderedMinor;

  int get totalMinor => lines.fold(0, (total, line) => total + line.lineTotalMinor);
  int get paidMinor => immediatePaymentMinor ?? totalMinor;
  int get balanceDueMinor => totalMinor - paidMinor;
  int? get cashChangeMinor {
    final tendered = cashTenderedMinor;
    if (paymentMethod != PaymentMethod.cash || tendered == null) return null;
    return tendered > paidMinor ? tendered - paidMinor : 0;
  }

  @override
  List<Object?> get props => [
        status,
        submission,
        errorMessage,
        lines,
        paymentMethod,
        customer,
        immediatePaymentMinor,
        cashTenderedMinor,
      ];
}

class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc(this._repository) : super(const CheckoutState()) {
    on<CheckoutSaleRequested>(_onSaleRequested);
    on<CheckoutReset>((event, emit) => emit(const CheckoutState()));
  }

  final SalesRepository _repository;

  Future<void> _onSaleRequested(
    CheckoutSaleRequested event,
    Emitter<CheckoutState> emit,
  ) async {
    if (state.status == CheckoutStatus.submitting || event.lines.isEmpty) return;
    final lines = List<CartLine>.unmodifiable(event.lines);
    final totalMinor = lines.fold<int>(0, (total, line) => total + line.lineTotalMinor);
    final paidMinor = event.immediatePaymentMinor ?? totalMinor;
    final creditMinor = totalMinor - paidMinor;

    if (paidMinor < 0 || paidMinor > totalMinor) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: 'Payment cannot be less than zero or greater than the sale total.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        customer: event.customer,
        immediatePaymentMinor: paidMinor,
        cashTenderedMinor: event.cashTenderedMinor,
      ));
      return;
    }
    if (creditMinor > 0 && event.customer == null) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: 'Select a customer before selling any amount on credit.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        immediatePaymentMinor: paidMinor,
      ));
      return;
    }
    if (creditMinor > 0 && !event.customer!.canCoverCredit(creditMinor)) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: 'The credit amount exceeds ${event.customer!.name}’s available credit.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        customer: event.customer,
        immediatePaymentMinor: paidMinor,
      ));
      return;
    }
    if (event.paymentMethod == PaymentMethod.cash &&
        paidMinor > 0 &&
        (event.cashTenderedMinor == null || event.cashTenderedMinor! < paidMinor)) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: 'Cash received cannot be less than the amount being paid now.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        customer: event.customer,
        immediatePaymentMinor: paidMinor,
        cashTenderedMinor: event.cashTenderedMinor,
      ));
      return;
    }

    emit(CheckoutState(
      status: CheckoutStatus.submitting,
      lines: lines,
      paymentMethod: event.paymentMethod,
      customer: event.customer,
      immediatePaymentMinor: paidMinor,
      cashTenderedMinor: event.cashTenderedMinor,
    ));
    try {
      final submission = await _repository.submitSale(
        lines: lines,
        paymentMethod: event.paymentMethod,
        customerId: event.customer?.id,
        immediatePaymentMinor: paidMinor,
      );
      emit(CheckoutState(
        status: CheckoutStatus.completed,
        submission: submission,
        lines: lines,
        paymentMethod: event.paymentMethod,
        customer: event.customer,
        immediatePaymentMinor: paidMinor,
        cashTenderedMinor: event.cashTenderedMinor,
      ));
    } catch (error) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: error is StateError ? error.message.toString() : 'The sale could not be saved.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        customer: event.customer,
        immediatePaymentMinor: paidMinor,
        cashTenderedMinor: event.cashTenderedMinor,
      ));
    }
  }
}
