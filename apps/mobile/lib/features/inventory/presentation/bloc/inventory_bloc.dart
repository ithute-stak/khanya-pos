import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';

sealed class InventoryEvent extends Equatable {
  const InventoryEvent();
  @override
  List<Object?> get props => [];
}

final class InventoryStarted extends InventoryEvent {
  const InventoryStarted();
}

final class InventoryRefreshRequested extends InventoryEvent {
  const InventoryRefreshRequested();
}

final class InventoryLowStockFilterChanged extends InventoryEvent {
  const InventoryLowStockFilterChanged(this.enabled);
  final bool enabled;
  @override
  List<Object?> get props => [enabled];
}

final class _InventoryProductsChanged extends InventoryEvent {
  const _InventoryProductsChanged(this.products);
  final List<ProductSummary> products;
  @override
  List<Object?> get props => [products];
}

class InventoryState extends Equatable {
  const InventoryState({
    this.products = const [],
    this.showLowStockOnly = false,
    this.isRefreshing = false,
    this.lastError,
  });

  final List<ProductSummary> products;
  final bool showLowStockOnly;
  final bool isRefreshing;
  final String? lastError;

  List<ProductSummary> get visibleProducts => showLowStockOnly
      ? products.where((product) => product.isLowStock).toList(growable: false)
      : products;
  int get lowStockCount => products.where((product) => product.isLowStock).length;

  InventoryState copyWith({
    List<ProductSummary>? products,
    bool? showLowStockOnly,
    bool? isRefreshing,
    String? lastError,
    bool clearError = false,
  }) =>
      InventoryState(
        products: products ?? this.products,
        showLowStockOnly: showLowStockOnly ?? this.showLowStockOnly,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  @override
  List<Object?> get props => [products, showLowStockOnly, isRefreshing, lastError];
}

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  InventoryBloc(this._repository) : super(const InventoryState()) {
    on<InventoryStarted>(_onStarted);
    on<InventoryRefreshRequested>(_onRefresh);
    on<InventoryLowStockFilterChanged>((event, emit) {
      emit(state.copyWith(showLowStockOnly: event.enabled));
    });
    on<_InventoryProductsChanged>((event, emit) {
      emit(state.copyWith(products: event.products));
    });
  }

  final ProductRepository _repository;
  StreamSubscription<List<ProductSummary>>? _subscription;

  Future<void> _onStarted(InventoryStarted event, Emitter<InventoryState> emit) async {
    await _subscription?.cancel();
    _subscription = _repository.watchCurrentCatalog().listen(
          (products) => add(_InventoryProductsChanged(products)),
        );
    add(const InventoryRefreshRequested());
  }

  Future<void> _onRefresh(InventoryRefreshRequested event, Emitter<InventoryState> emit) async {
    if (state.isRefreshing) return;
    emit(state.copyWith(isRefreshing: true, clearError: true));
    try {
      await _repository.refresh();
      emit(state.copyWith(isRefreshing: false, clearError: true));
    } catch (_) {
      emit(state.copyWith(
        isRefreshing: false,
        lastError: state.products.isEmpty
            ? 'Inventory is not available yet.'
            : 'Showing saved inventory while offline.',
      ));
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
