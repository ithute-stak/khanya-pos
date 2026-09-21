import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_service.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';

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

final class _SyncPendingCountChanged extends SyncEvent {
  const _SyncPendingCountChanged(this.count);
  final int count;
  @override
  List<Object?> get props => [count];
}

final class _SyncConflictCountChanged extends SyncEvent {
  const _SyncConflictCountChanged(this.count);
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
    required SyncService syncService,
    required ProductRepository productRepository,
  })  : _database = database,
        _syncService = syncService,
        _productRepository = productRepository,
        super(const SyncStatusState()) {
    on<SyncStarted>(_onStarted);
    on<SyncRequested>(_onRequested);
    on<_SyncPendingCountChanged>((event, emit) => emit(state.copyWith(pendingCount: event.count)));
    on<_SyncConflictCountChanged>((event, emit) => emit(state.copyWith(conflictCount: event.count)));
  }

  final AppDatabase _database;
  final SyncService _syncService;
  final ProductRepository _productRepository;
  StreamSubscription<int>? _pendingSubscription;
  StreamSubscription<int>? _conflictSubscription;
  bool _running = false;

  Future<void> _onStarted(SyncStarted event, Emitter<SyncStatusState> emit) async {
    await _pendingSubscription?.cancel();
    await _conflictSubscription?.cancel();
    _pendingSubscription = _database.watchPendingCount().listen(
          (count) => add(_SyncPendingCountChanged(count)),
        );
    _conflictSubscription = _database.watchConflictCount().listen(
          (count) => add(_SyncConflictCountChanged(count)),
        );
  }

  Future<void> _onRequested(SyncRequested event, Emitter<SyncStatusState> emit) async {
    if (_running) return;
    _running = true;
    emit(state.copyWith(isSyncing: true));
    try {
      final result = await _syncService.flushPendingSales();
      if (result.synced > 0 || result.conflicts > 0) {
        try {
          await _productRepository.refresh();
        } catch (_) {
          // Local state remains available; reconciliation will retry later.
        }
      }
      final message = result.networkUnavailable
          ? 'Offline — queued sales will sync automatically.'
          : result.conflicts > 0
              ? '${result.conflicts} sale(s) need sync review.'
              : result.synced > 0
                  ? '${result.synced} sale(s) synced.'
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
    await _pendingSubscription?.cancel();
    await _conflictSubscription?.cancel();
    return super.close();
  }
}
