import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/expenses/data/expense_repository.dart';
import 'package:khanya_pos/features/expenses/domain/expense_summary.dart';

sealed class ExpensesEvent extends Equatable {
  const ExpensesEvent();
  @override
  List<Object?> get props => [];
}

final class ExpensesRequested extends ExpensesEvent {
  const ExpensesRequested();
}

final class ExpenseCreateRequested extends ExpensesEvent {
  const ExpenseCreateRequested({
    required this.category,
    required this.description,
    required this.amountText,
    required this.paymentMethod,
    this.receiptDocumentId,
  });
  final String category;
  final String description;
  final String amountText;
  final String paymentMethod;
  final String? receiptDocumentId;

  @override
  List<Object?> get props => [category, description, amountText, paymentMethod, receiptDocumentId];
}

class ExpensesState extends Equatable {
  const ExpensesState({
    this.items = const [],
    this.loading = false,
    this.saving = false,
    this.saved = false,
    this.message,
  });

  final List<ExpenseSummary> items;
  final bool loading;
  final bool saving;
  final bool saved;
  final String? message;

  @override
  List<Object?> get props => [items, loading, saving, saved, message];
}

class ExpensesBloc extends Bloc<ExpensesEvent, ExpensesState> {
  ExpensesBloc({required ExpenseRepository repository})
      : _repository = repository,
        super(const ExpensesState()) {
    on<ExpensesRequested>(_onRequested);
    on<ExpenseCreateRequested>(_onCreateRequested);
  }

  final ExpenseRepository _repository;

  Future<void> _onRequested(ExpensesRequested event, Emitter<ExpensesState> emit) async {
    emit(ExpensesState(items: state.items, loading: true));
    try {
      emit(ExpensesState(items: await _repository.listExpenses()));
    } catch (_) {
      emit(ExpensesState(items: state.items, message: 'Could not load expenses.'));
    }
  }

  Future<void> _onCreateRequested(
    ExpenseCreateRequested event,
    Emitter<ExpensesState> emit,
  ) async {
    final amountMinor = ScaledDecimal.toMinor(event.amountText);
    if (amountMinor <= 0 || event.description.trim().length < 2) {
      emit(ExpensesState(items: state.items, message: 'Enter a valid description and amount.'));
      return;
    }
    emit(ExpensesState(items: state.items, saving: true));
    try {
      final queued = await _repository.createExpense(
        category: event.category,
        description: event.description,
        amountMinor: amountMinor,
        paymentMethod: event.paymentMethod,
        receiptDocumentId: event.receiptDocumentId,
      );
      emit(
        ExpensesState(
          items: state.items,
          saved: true,
          message: queued
              ? 'Expense saved on this device and queued for sync.'
              : 'Expense saved and synced.',
        ),
      );
    } catch (_) {
      emit(ExpensesState(items: state.items, message: 'Could not save expense. Review the values and try again.'));
    }
  }
}
