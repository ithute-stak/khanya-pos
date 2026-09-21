import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/customers/data/customer_database.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';

sealed class SyncEvent extends Equatable {
  const SyncEvent();
  @override
  List<Object?> get props => [];
}

final class SyncStarted extends SyncEvent {
  const SyncStarted();
}

final class SyncRequested extends SyncEvent {
  const SyncRequested();
}

final class _PrimaryPendingCountChanged extends SyncEvent {
  const _PrimaryPendingCountChanged(this.count);
  final int count;
  @override
  List<Object?> get props => [count];
}

final class _CustomerPendingCountChanged extends SyncEvent {
  const _CustomerPendingCountChanged(this.count);
  final int count;
  @override
  List<Object?> get props => [count];
}

final class _PrimaryConflictCountChanged extends SyncEvent {
  const _PrimaryConflictCountChanged(this.count);
  final int count;
  @override
  List<Object?> get props => [count];
}

final class _CustomerConflictCountChanged extends SyncEvent {
  const _CustomerConflictCountChanged(this.count);
  final int count;
  @override
  List<Object?> get props => [count];
}

class SyncStatusState extends Equatable {
  const SyncStatusState({
    this.pendingCount = 0,
    this.conflictCount = 0,
    this.isSyncing = false,
    this.lastMessage,
  });

  final int pendingCount;
  final int conflictCount;
  final bool isSyncing;
  final String? lastMessage;

  SyncStatusState copyWith({
    int? pendingCount,
    int? conflictCount,
    bool? isSyncing,
    String? lastMessage,
  }) =>
      SyncStatusState(
        pendingCount: pendingCount ?? this.pendingCount,
        conflictCount: conflictCount ?? this.conflictCount,
        isSyncing: isSyncing ?? this.isSyncing,
        lastMessage: lastMessage ?? this.lastMessage,
      );

  @override
  List<Object?> get props => [pendingCount, conflictCount, isSyncing, lastMessage];
}

class SyncBloc extends Bloc<SyncEvent, SyncStatusState> {
  SyncBloc({
    required AppDatabase database,
    required CustomerDatabase customerDatabase,
    required SyncService syncService,
    required ProductRepository productRepository,
    required CustomerRepository customerRepository,
  })  : _database = database,
        _customerDatabase = customerDatabase,
        _syncService = syncService,
        _productRepository = productRepository,
        _customerRepository = customerRepository,
        super(const SyncStatusState()) {
    on<SyncStarted>(_onStarted);
    on<SyncRequested>(_onRequested);
    on<_PrimaryPendingCountChanged>((event, emit) {
      _primaryPending = event.count;
      emit(state.copyWith(pendingCount: _primaryPending + _customerPending));
    });
    on<_CustomerPendingCountChanged>((event, emit) {
      _customerPending = event.count;
      emit(state.copyWith(pendingCount: _primaryPending + _customerPending));
    });
    on<_PrimaryConflictCountChanged>((event, emit) {
      _primaryConflicts = event.count;
      emit(state.copyWith(conflictCount: _primaryConflicts + _customerConflicts));
    });
    on<_CustomerConflictCountChanged>((event, emit) {
      _customerConflicts = event.count;
      emit(state.copyWith(conflictCount: _primaryConflicts + _customerConflicts));
    });
  }

  final AppDatabase _database;
  final CustomerDatabase _customerDatabase;
  final SyncService _syncService;
  final ProductRepository _productRepository;
  final CustomerRepository _customerRepository;
  StreamSubscription<int>? _primaryPendingSubscription;
  StreamSubscription<int>? _customerPendingSubscription;
  StreamSubscription<int>? _primaryConflictSubscription;
  StreamSubscription<int>? _customerConflictSubscription;
  int _primaryPending = 0;
  int _customerPending = 0;
  int _primaryConflicts = 0;
  int _customerConflicts = 0;
  bool _running = false;

  Future<void> _onStarted(SyncStarted event, Emitter<SyncStatusState> emit) async {
    await _primaryPendingSubscription?.cancel();
    await _customerPendingSubscription?.cancel();
    await _primaryConflictSubscription?.cancel();
    await _customerConflictSubscription?.cancel();

    _primaryPendingSubscription = _database.watchPendingCount().listen(
          (count) => add(_PrimaryPendingCountChanged(count)),
        );
    _customerPendingSubscription = _customerDatabase.watchPendingCount().listen(
          (count) => add(_CustomerPendingCountChanged(count)),
        );
    _primaryConflictSubscription = _database.watchConflictCount().listen(
          (count) => add(_PrimaryConflictCountChanged(count)),
        );
    _customerConflictSubscription = _customerDatabase.watchConflictCount().listen(
          (count) => add(_CustomerConflictCountChanged(count)),
        );
  }

  Future<void> _onRequested(SyncRequested event, Emitter<SyncStatusState> emit) async {
    if (_running) return;
    _running = true;
    emit(state.copyWith(isSyncing: true));
    try {
      // The customer and sales projections live in separate local databases.
      // Repair an orphaned credit reservation first in case the app was killed
      // after reserving credit but before the sale outbox write completed.
      try {
        await _customerRepository.reconcileOfflineProjections();
      } catch (_) {
        // No business may be selected yet. A later authenticated sync will retry.
      }

      final result = await _syncService.flushAll();
      if (result.synced > 0 || result.conflicts > 0) {
        try {
          await _productRepository.refresh();
        } catch (_) {
          // Local stock projections remain available; reconciliation will retry later.
        }
        try {
          await _customerRepository.refresh();
        } catch (_) {
          // Local receivable projections remain available; reconciliation will retry later.
        }
      }
      final message = result.networkUnavailable
          ? 'Offline — saved work will sync automatically.'
          : result.conflicts > 0
              ? '${result.conflicts} item(s) need sync review.'
              : result.synced > 0
                  ? '${result.synced} queued item(s) synced.'
                  : null;
      emit(state.copyWith(isSyncing: false, lastMessage: message));
    } catch (_) {
      emit(state.copyWith(isSyncing: false, lastMessage: 'Sync will retry when connectivity improves.'));
    } finally {
      _running = false;
    }
  }

  @override
  Future<void> close() async {
    await _primaryPendingSubscription?.cancel();
    await _customerPendingSubscription?.cancel();
    await _primaryConflictSubscription?.cancel();
    await _customerConflictSubscription?.cancel();
    return super.close();
  }
}
