import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';

sealed class SuppliersEvent extends Equatable {
  const SuppliersEvent();
  @override
  List<Object?> get props => [];
}

final class SuppliersRequested extends SuppliersEvent {
  const SuppliersRequested();
}

final class SupplierCreateRequested extends SuppliersEvent {
  const SupplierCreateRequested({required this.code, required this.name, this.phone});
  final String code;
  final String name;
  final String? phone;
  @override
  List<Object?> get props => [code, name, phone];
}

class SuppliersState extends Equatable {
  const SuppliersState({this.items = const [], this.loading = false, this.saving = false, this.message});
  final List<SupplierSummary> items;
  final bool loading;
  final bool saving;
  final String? message;

  @override
  List<Object?> get props => [items, loading, saving, message];
}

class SuppliersBloc extends Bloc<SuppliersEvent, SuppliersState> {
  SuppliersBloc({required PurchasingRepository repository})
      : _repository = repository,
        super(const SuppliersState()) {
    on<SuppliersRequested>(_onRequested);
    on<SupplierCreateRequested>(_onCreateRequested);
  }

  final PurchasingRepository _repository;

  Future<void> _onRequested(SuppliersRequested event, Emitter<SuppliersState> emit) async {
    emit(SuppliersState(items: state.items, loading: true));
    try {
      emit(SuppliersState(items: await _repository.listSuppliers()));
    } catch (_) {
      emit(SuppliersState(items: state.items, message: 'Could not load suppliers.'));
    }
  }

  Future<void> _onCreateRequested(
    SupplierCreateRequested event,
    Emitter<SuppliersState> emit,
  ) async {
    emit(SuppliersState(items: state.items, saving: true));
    try {
      await _repository.createSupplier(code: event.code, name: event.name, phone: event.phone);
      emit(SuppliersState(items: await _repository.listSuppliers(), message: 'Supplier created.'));
    } catch (_) {
      emit(SuppliersState(items: state.items, message: 'Could not create supplier. Check the code and connection.'));
    }
  }
}
