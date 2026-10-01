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
    this.checkoutTotalMinor,
    this.promotionCode,
    this.loyaltyPointsToRedeem = 0,
  });

  final List<CartLine> lines;
  final PaymentMethod paymentMethod;
  final CustomerSummary? customer;
  final int? immediatePaymentMinor;
  final int? cashTenderedMinor;
  final int? checkoutTotalMinor;
  final String? promotionCode;
  final int loyaltyPointsToRedeem;

  @override
  List<Object?> get props => [
        lines,
        paymentMethod,
        customer,
        immediatePaymentMinor,
        cashTenderedMinor,
        checkoutTotalMinor,
        promotionCode,
        loyaltyPointsToRedeem,
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
    this.checkoutTotalMinor,
    this.promotionCode,
    this.loyaltyPointsToRedeem = 0,
  });

  final CheckoutStatus status;
  final SaleSubmission? submission;
  final String? errorMessage;
  final List<CartLine> lines;
  final PaymentMethod? paymentMethod;
  final CustomerSummary? customer;
  final int? immediatePaymentMinor;
  final int? cashTenderedMinor;
  final int? checkoutTotalMinor;
  final String? promotionCode;
  final int loyaltyPointsToRedeem;

  int get grossTotalMinor => lines.fold(0, (total, line) => total + line.lineTotalMinor);
  int get totalMinor => checkoutTotalMinor ?? grossTotalMinor;
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
        checkoutTotalMinor,
        promotionCode,
        loyaltyPointsToRedeem,
      ];
}

class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc(this._repository) : super(const CheckoutState()) {
    on<CheckoutSaleRequested>(_onSaleRequested);
    on<CheckoutReset>((event, emit) {
      _repository.clearCheckoutBenefits();
      emit(const CheckoutState());
    });
  }

  final SalesRepository _repository;

  Future<void> _onSaleRequested(
    CheckoutSaleRequested event,
    Emitter<CheckoutState> emit,
  ) async {
    if (state.status == CheckoutStatus.submitting || event.lines.isEmpty) return;
    final lines = List<CartLine>.unmodifiable(event.lines);
    final grossTotalMinor = lines.fold<int>(0, (total, line) => total + line.lineTotalMinor);
    final configuredBenefits = _repository.checkoutBenefits;
    final benefits = configuredBenefits != null && configuredBenefits.grossTotalMinor == grossTotalMinor
        ? configuredBenefits
        : null;
    final totalMinor = event.checkoutTotalMinor ?? benefits?.checkoutTotalMinor ?? grossTotalMinor;
    var paidMinor = event.immediatePaymentMinor ?? totalMinor;
    if (paidMinor == grossTotalMinor && totalMinor < grossTotalMinor) {
      paidMinor = totalMinor;
    }
    if (paidMinor > totalMinor) paidMinor = totalMinor;
    final creditMinor = totalMinor - paidMinor;
    final promotionCode = event.promotionCode ?? benefits?.promotionCode;
    final loyaltyPointsToRedeem = event.loyaltyPointsToRedeem > 0
        ? event.loyaltyPointsToRedeem
        : benefits?.loyaltyPointsToRedeem ?? 0;

    if (totalMinor < 0 || totalMinor > grossTotalMinor) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: 'Discounted total cannot be below zero or above the basket total.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        customer: event.customer,
        checkoutTotalMinor: totalMinor,
      ));
      return;
    }
    if (paidMinor < 0 || paidMinor > totalMinor) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: 'Payment cannot be less than zero or greater than the sale total.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        customer: event.customer,
        immediatePaymentMinor: paidMinor,
        cashTenderedMinor: event.cashTenderedMinor,
        checkoutTotalMinor: totalMinor,
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
        checkoutTotalMinor: totalMinor,
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
        checkoutTotalMinor: totalMinor,
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
        checkoutTotalMinor: totalMinor,
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
      checkoutTotalMinor: totalMinor,
      promotionCode: promotionCode,
      loyaltyPointsToRedeem: loyaltyPointsToRedeem,
    ));
    try {
      final submission = await _repository.submitSale(
        lines: lines,
        paymentMethod: event.paymentMethod,
        customerId: event.customer?.id,
        immediatePaymentMinor: paidMinor,
        checkoutTotalMinor: totalMinor,
        promotionCode: promotionCode,
        loyaltyPointsToRedeem: loyaltyPointsToRedeem,
      );
      _repository.clearCheckoutBenefits();
      emit(CheckoutState(
        status: CheckoutStatus.completed,
        submission: submission,
        lines: lines,
        paymentMethod: event.paymentMethod,
        customer: event.customer,
        immediatePaymentMinor: paidMinor,
        cashTenderedMinor: event.cashTenderedMinor,
        checkoutTotalMinor: totalMinor,
        promotionCode: promotionCode,
        loyaltyPointsToRedeem: loyaltyPointsToRedeem,
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
        checkoutTotalMinor: totalMinor,
        promotionCode: promotionCode,
        loyaltyPointsToRedeem: loyaltyPointsToRedeem,
      ));
    }
  }
}
