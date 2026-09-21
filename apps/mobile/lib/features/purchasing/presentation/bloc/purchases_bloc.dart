import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';

sealed class PurchasesEvent extends Equatable {
  const PurchasesEvent();
  @override
  List<Object?> get props => [];
}

final class PurchasesRequested extends PurchasesEvent {
  const PurchasesRequested();
}

class PurchasesState extends Equatable {
  const PurchasesState({this.items = const [], this.loading = false, this.message});
  final List<PurchaseSummary> items;
  final bool loading;
  final String? message;

  @override
  List<Object?> get props => [items, loading, message];
}

class PurchasesBloc extends Bloc<PurchasesEvent, PurchasesState> {
  PurchasesBloc({required PurchasingRepository repository})
      : _repository = repository,
        super(const PurchasesState()) {
    on<PurchasesRequested>(_onRequested);
  }

  final PurchasingRepository _repository;

  Future<void> _onRequested(PurchasesRequested event, Emitter<PurchasesState> emit) async {
    emit(PurchasesState(items: state.items, loading: true));
    try {
      emit(PurchasesState(items: await _repository.listPurchases()));
    } catch (_) {
      emit(PurchasesState(items: state.items, message: 'Could not load purchases.'));
    }
  }
}
