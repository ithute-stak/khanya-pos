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
  const CheckoutSaleRequested({required this.lines, required this.paymentMethod});
  final List<CartLine> lines;
  final PaymentMethod paymentMethod;
  @override
  List<Object?> get props => [lines, paymentMethod];
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
  });

  final CheckoutStatus status;
  final SaleSubmission? submission;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, submission, errorMessage];
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
    emit(const CheckoutState(status: CheckoutStatus.submitting));
    try {
      final submission = await _repository.submitSale(
        lines: event.lines,
        paymentMethod: event.paymentMethod,
      );
      emit(CheckoutState(status: CheckoutStatus.completed, submission: submission));
    } catch (error) {
      emit(CheckoutState(
        status: CheckoutStatus.failed,
        errorMessage: error is StateError ? error.message.toString() : 'The sale could not be saved.',
      ));
    }
  }
}
