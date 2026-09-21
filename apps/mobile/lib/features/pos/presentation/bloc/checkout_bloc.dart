import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    this.cashTenderedMinor,
  });

  final List<CartLine> lines;
  final PaymentMethod paymentMethod;
  final int? cashTenderedMinor;

  @override
  List<Object?> get props => [lines, paymentMethod, cashTenderedMinor];
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
    this.cashTenderedMinor,
  });

  final CheckoutStatus status;
  final SaleSubmission? submission;
  final String? errorMessage;
  final List<CartLine> lines;
  final PaymentMethod? paymentMethod;
  final int? cashTenderedMinor;

  int get totalMinor => lines.fold(0, (total, line) => total + line.lineTotalMinor);
  int? get cashChangeMinor {
    final tendered = cashTenderedMinor;
    if (paymentMethod != PaymentMethod.cash || tendered == null) return null;
    return tendered > totalMinor ? tendered - totalMinor : 0;
  }

  @override
  List<Object?> get props => [
        status,
        submission,
        errorMessage,
        lines,
        paymentMethod,
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
    if (event.paymentMethod == PaymentMethod.cash &&
        (event.cashTenderedMinor == null || event.cashTenderedMinor! < totalMinor)) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: 'Cash received cannot be less than the amount due.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        cashTenderedMinor: event.cashTenderedMinor,
      ));
      return;
    }

    emit(CheckoutState(
      status: CheckoutStatus.submitting,
      lines: lines,
      paymentMethod: event.paymentMethod,
      cashTenderedMinor: event.cashTenderedMinor,
    ));
    try {
      final submission = await _repository.submitSale(
        lines: lines,
        paymentMethod: event.paymentMethod,
      );
      emit(CheckoutState(
        status: CheckoutStatus.completed,
        submission: submission,
        lines: lines,
        paymentMethod: event.paymentMethod,
        cashTenderedMinor: event.cashTenderedMinor,
      ));
    } catch (error) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: error is StateError ? error.message.toString() : 'The sale could not be saved.',
        lines: lines,
        paymentMethod: event.paymentMethod,
        cashTenderedMinor: event.cashTenderedMinor,
      ));
    }
  }
}
