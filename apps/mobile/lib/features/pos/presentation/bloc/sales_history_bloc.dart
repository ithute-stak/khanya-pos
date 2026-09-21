import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/pos/data/sales_repository.dart';
import 'package:khanya_pos/features/pos/domain/sales_history.dart';

enum SalesHistoryStatus { initial, loading, ready, failure }

class SalesHistoryState extends Equatable {
  const SalesHistoryState({
    this.status = SalesHistoryStatus.initial,
    this.sales = const [],
    this.search = '',
    this.errorMessage,
  });

  final SalesHistoryStatus status;
  final List<SaleHistoryEntry> sales;
  final String search;
  final String? errorMessage;

  @override
  List<Object?> get props => [status, sales, search, errorMessage];
}

class SalesHistoryCubit extends Cubit<SalesHistoryState> {
  SalesHistoryCubit({required SalesRepository repository})
      : _repository = repository,
        super(const SalesHistoryState());

  final SalesRepository _repository;

  Future<void> load({String? search}) async {
    final query = search ?? state.search;
    emit(SalesHistoryState(
      status: SalesHistoryStatus.loading,
      sales: state.sales,
      search: query,
    ));
    try {
      final sales = await _repository.history(search: query);
      emit(SalesHistoryState(
        status: SalesHistoryStatus.ready,
        sales: List.unmodifiable(sales),
        search: query,
      ));
    } catch (error) {
      emit(SalesHistoryState(
        status: SalesHistoryStatus.failure,
        sales: state.sales,
        search: query,
        errorMessage: _message(error, 'Sales history could not be loaded.'),
      ));
    }
  }
}

enum SaleDetailStatus { initial, loading, ready, submitting, failure }

class SaleDetailState extends Equatable {
  const SaleDetailState({
    this.status = SaleDetailStatus.initial,
    this.sale,
    this.errorMessage,
    this.notice,
  });

  final SaleDetailStatus status;
  final SaleDetail? sale;
  final String? errorMessage;
  final String? notice;

  bool get busy => status == SaleDetailStatus.loading || status == SaleDetailStatus.submitting;

  @override
  List<Object?> get props => [status, sale, errorMessage, notice];
}

class SaleDetailCubit extends Cubit<SaleDetailState> {
  SaleDetailCubit({required SalesRepository repository, required this.saleId})
      : _repository = repository,
        super(const SaleDetailState());

  final SalesRepository _repository;
  final String saleId;

  Future<void> load() async {
    emit(SaleDetailState(
      status: SaleDetailStatus.loading,
      sale: state.sale,
    ));
    try {
      final sale = await _repository.detail(saleId);
      emit(SaleDetailState(status: SaleDetailStatus.ready, sale: sale));
    } catch (error) {
      emit(SaleDetailState(
        status: SaleDetailStatus.failure,
        sale: state.sale,
        errorMessage: _message(error, 'Sale details could not be loaded.'),
      ));
    }
  }

  Future<bool> returnItems({
    required Map<String, int> quantitiesMilliByLine,
    required String reason,
    required String refundMethod,
    String? refundReference,
  }) async {
    if (state.status == SaleDetailStatus.submitting) return false;
    emit(SaleDetailState(
      status: SaleDetailStatus.submitting,
      sale: state.sale,
    ));
    try {
      await _repository.returnItems(
        saleId: saleId,
        quantitiesMilliByLine: quantitiesMilliByLine,
        reason: reason,
        refundMethod: refundMethod,
        refundReference: refundReference,
      );
      final sale = await _repository.detail(saleId);
      emit(SaleDetailState(
        status: SaleDetailStatus.ready,
        sale: sale,
        notice: 'Return processed and stock restored.',
      ));
      return true;
    } catch (error) {
      emit(SaleDetailState(
        status: SaleDetailStatus.failure,
        sale: state.sale,
        errorMessage: _message(error, 'Return could not be processed.'),
      ));
      return false;
    }
  }

  Future<bool> voidSale({
    required String reason,
    required String refundMethod,
    String? refundReference,
  }) async {
    if (state.status == SaleDetailStatus.submitting) return false;
    emit(SaleDetailState(
      status: SaleDetailStatus.submitting,
      sale: state.sale,
    ));
    try {
      await _repository.voidSale(
        saleId: saleId,
        reason: reason,
        refundMethod: refundMethod,
        refundReference: refundReference,
      );
      final sale = await _repository.detail(saleId);
      emit(SaleDetailState(
        status: SaleDetailStatus.ready,
        sale: sale,
        notice: 'Sale void completed and financial reversal posted.',
      ));
      return true;
    } catch (error) {
      emit(SaleDetailState(
        status: SaleDetailStatus.failure,
        sale: state.sale,
        errorMessage: _message(error, 'Sale could not be voided.'),
      ));
      return false;
    }
  }
}

String _message(Object error, String fallback) {
  if (error is StateError) return error.message.toString();
  return fallback;
}
