import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';

sealed class ProductCatalogEvent extends Equatable {
  const ProductCatalogEvent();
  @override
  List<Object?> get props => [];
}

final class ProductCatalogStarted extends ProductCatalogEvent {
  const ProductCatalogStarted();
}

final class ProductCatalogRefreshRequested extends ProductCatalogEvent {
  const ProductCatalogRefreshRequested();
}

final class ProductCatalogQueryChanged extends ProductCatalogEvent {
  const ProductCatalogQueryChanged(this.query);
  final String query;
  @override
  List<Object?> get props => [query];
}

final class _ProductCatalogLocalChanged extends ProductCatalogEvent {
  const _ProductCatalogLocalChanged(this.products);
  final List<ProductSummary> products;
  @override
  List<Object?> get props => [products];
}

class ProductCatalogState extends Equatable {
  const ProductCatalogState({
    this.products = const [],
    this.query = '',
    this.isRefreshing = false,
    this.lastError,
  });

  final List<ProductSummary> products;
  final String query;
  final bool isRefreshing;
  final String? lastError;

  List<ProductSummary> get visibleProducts {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return products;
    return products.where((product) {
      return product.name.toLowerCase().contains(normalized) ||
          product.sku.toLowerCase().contains(normalized) ||
          (product.barcode?.toLowerCase().contains(normalized) ?? false);
    }).toList(growable: false);
  }

  ProductCatalogState copyWith({
    List<ProductSummary>? products,
    String? query,
    bool? isRefreshing,
    String? lastError,
    bool clearError = false,
  }) =>
      ProductCatalogState(
        products: products ?? this.products,
        query: query ?? this.query,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  @override
  List<Object?> get props => [products, query, isRefreshing, lastError];
}

class ProductCatalogBloc extends Bloc<ProductCatalogEvent, ProductCatalogState> {
  ProductCatalogBloc(this._repository) : super(const ProductCatalogState()) {
    on<ProductCatalogStarted>(_onStarted);
    on<ProductCatalogRefreshRequested>(_onRefresh);
    on<ProductCatalogQueryChanged>((event, emit) => emit(state.copyWith(query: event.query)));
    on<_ProductCatalogLocalChanged>((event, emit) {
      emit(state.copyWith(products: event.products));
    });
  }

  final ProductRepository _repository;
  StreamSubscription<List<ProductSummary>>? _subscription;

  Future<void> _onStarted(ProductCatalogStarted event, Emitter<ProductCatalogState> emit) async {
    await _subscription?.cancel();
    _subscription = _repository.watchCurrentCatalog().listen(
          (products) => add(_ProductCatalogLocalChanged(products)),
        );
    add(const ProductCatalogRefreshRequested());
  }

  Future<void> _onRefresh(
    ProductCatalogRefreshRequested event,
    Emitter<ProductCatalogState> emit,
  ) async {
    if (state.isRefreshing) return;
    emit(state.copyWith(isRefreshing: true, clearError: true));
    try {
      await _repository.refresh();
      emit(state.copyWith(isRefreshing: false, clearError: true));
    } catch (error) {
      emit(state.copyWith(
        isRefreshing: false,
        lastError: state.products.isEmpty
            ? 'Unable to load products. Connect to the internet and retry.'
            : 'Showing saved products. Live refresh is unavailable.',
      ));
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
