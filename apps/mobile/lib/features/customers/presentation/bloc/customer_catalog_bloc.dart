import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';

sealed class CustomerCatalogEvent extends Equatable {
  const CustomerCatalogEvent();

  @override
  List<Object?> get props => [];
}

final class CustomerCatalogStarted extends CustomerCatalogEvent {
  const CustomerCatalogStarted();
}

final class CustomerCatalogRefreshRequested extends CustomerCatalogEvent {
  const CustomerCatalogRefreshRequested();
}

final class CustomerCatalogQueryChanged extends CustomerCatalogEvent {
  const CustomerCatalogQueryChanged(this.query);
  final String query;

  @override
  List<Object?> get props => [query];
}

final class _CustomerCatalogLocalChanged extends CustomerCatalogEvent {
  const _CustomerCatalogLocalChanged(this.customers);
  final List<CustomerSummary> customers;

  @override
  List<Object?> get props => [customers];
}

class CustomerCatalogState extends Equatable {
  const CustomerCatalogState({
    this.customers = const [],
    this.query = '',
    this.isRefreshing = false,
    this.lastError,
  });

  final List<CustomerSummary> customers;
  final String query;
  final bool isRefreshing;
  final String? lastError;

  List<CustomerSummary> get visibleCustomers {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return customers;
    return customers.where((customer) {
      return customer.name.toLowerCase().contains(normalized) ||
          customer.code.toLowerCase().contains(normalized) ||
          (customer.phone?.toLowerCase().contains(normalized) ?? false) ||
          (customer.email?.toLowerCase().contains(normalized) ?? false);
    }).toList(growable: false);
  }

  int get totalOutstandingMinor =>
      customers.fold(0, (total, customer) => total + customer.outstandingMinor);

  CustomerCatalogState copyWith({
    List<CustomerSummary>? customers,
    String? query,
    bool? isRefreshing,
    String? lastError,
    bool clearError = false,
  }) =>
      CustomerCatalogState(
        customers: customers ?? this.customers,
        query: query ?? this.query,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  @override
  List<Object?> get props => [customers, query, isRefreshing, lastError];
}

class CustomerCatalogBloc extends Bloc<CustomerCatalogEvent, CustomerCatalogState> {
  CustomerCatalogBloc(this._repository) : super(const CustomerCatalogState()) {
    on<CustomerCatalogStarted>(_onStarted);
    on<CustomerCatalogRefreshRequested>(_onRefresh);
    on<CustomerCatalogQueryChanged>((event, emit) => emit(state.copyWith(query: event.query)));
    on<_CustomerCatalogLocalChanged>((event, emit) {
      emit(state.copyWith(customers: event.customers));
    });
  }

  final CustomerRepository _repository;
  StreamSubscription<List<CustomerSummary>>? _subscription;

  Future<void> _onStarted(CustomerCatalogStarted event, Emitter<CustomerCatalogState> emit) async {
    await _subscription?.cancel();
    _subscription = _repository.watchCurrentCustomers().listen(
          (customers) => add(_CustomerCatalogLocalChanged(customers)),
        );
    try {
      final cached = await _repository.cachedCustomers();
      add(_CustomerCatalogLocalChanged(cached));
    } catch (_) {
      // A selected business may still be restoring. The refresh below owns the user-facing error.
    }
    add(const CustomerCatalogRefreshRequested());
  }

  Future<void> _onRefresh(
    CustomerCatalogRefreshRequested event,
    Emitter<CustomerCatalogState> emit,
  ) async {
    if (state.isRefreshing) return;
    emit(state.copyWith(isRefreshing: true, clearError: true));
    try {
      await _repository.refresh();
      emit(state.copyWith(isRefreshing: false, clearError: true));
    } catch (_) {
      emit(state.copyWith(
        isRefreshing: false,
        lastError: state.customers.isEmpty
            ? 'Unable to load customers. Connect to the internet and retry.'
            : 'Showing saved customers and credit positions. Live refresh is unavailable.',
      ));
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
