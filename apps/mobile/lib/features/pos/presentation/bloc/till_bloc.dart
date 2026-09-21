import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/pos/data/till_repository.dart';
import 'package:khanya_pos/features/pos/domain/till_shift.dart';

enum TillLoadStatus { initial, loading, ready, submitting, failure }

sealed class TillEvent extends Equatable {
  const TillEvent();

  @override
  List<Object?> get props => const [];
}

class TillStarted extends TillEvent {
  const TillStarted();
}

class TillRefreshed extends TillEvent {
  const TillRefreshed();
}

class TillOpened extends TillEvent {
  const TillOpened(this.openingFloatMinor);

  final int openingFloatMinor;

  @override
  List<Object?> get props => [openingFloatMinor];
}

class TillCashMovementRecorded extends TillEvent {
  const TillCashMovementRecorded({
    required this.movementType,
    required this.amountMinor,
    required this.reason,
  });

  final String movementType;
  final int amountMinor;
  final String reason;

  @override
  List<Object?> get props => [movementType, amountMinor, reason];
}

class TillClosed extends TillEvent {
  const TillClosed({required this.countedCashMinor, this.note});

  final int countedCashMinor;
  final String? note;

  @override
  List<Object?> get props => [countedCashMinor, note];
}

class TillState extends Equatable {
  const TillState({
    this.status = TillLoadStatus.initial,
    this.current,
    this.history = const [],
    this.pendingCashSalesCount = 0,
    this.errorMessage,
    this.notice,
  });

  final TillLoadStatus status;
  final TillShiftSummary? current;
  final List<TillShiftSummary> history;
  final int pendingCashSalesCount;
  final String? errorMessage;
  final String? notice;

  bool get busy => status == TillLoadStatus.loading || status == TillLoadStatus.submitting;
  bool get reconciliationReady => pendingCashSalesCount == 0;

  TillState copyWith({
    TillLoadStatus? status,
    TillShiftSummary? current,
    bool clearCurrent = false,
    List<TillShiftSummary>? history,
    int? pendingCashSalesCount,
    String? errorMessage,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
  }) {
    return TillState(
      status: status ?? this.status,
      current: clearCurrent ? null : current ?? this.current,
      history: history ?? this.history,
      pendingCashSalesCount: pendingCashSalesCount ?? this.pendingCashSalesCount,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      notice: clearNotice ? null : notice ?? this.notice,
    );
  }

  @override
  List<Object?> get props => [
        status,
        current,
        history,
        pendingCashSalesCount,
        errorMessage,
        notice,
      ];
}

class TillBloc extends Bloc<TillEvent, TillState> {
  TillBloc({required TillRepository repository})
      : _repository = repository,
        super(const TillState()) {
    on<TillStarted>(_onLoad);
    on<TillRefreshed>(_onLoad);
    on<TillOpened>(_onOpen);
    on<TillCashMovementRecorded>(_onMovement);
    on<TillClosed>(_onClose);
  }

  final TillRepository _repository;

  Future<void> _onLoad(TillEvent event, Emitter<TillState> emit) async {
    emit(state.copyWith(
      status: TillLoadStatus.loading,
      clearError: true,
      clearNotice: true,
    ));
    try {
      final current = await _repository.current();
      final history = await _repository.history();
      final pendingCashSalesCount = await _repository.pendingCashSalesCount();
      emit(TillState(
        status: TillLoadStatus.ready,
        current: current,
        history: List.unmodifiable(history),
        pendingCashSalesCount: pendingCashSalesCount,
      ));
    } catch (error) {
      emit(state.copyWith(
        status: TillLoadStatus.failure,
        errorMessage: _message(error),
        clearNotice: true,
      ));
    }
  }

  Future<void> _onOpen(TillOpened event, Emitter<TillState> emit) async {
    if (state.status == TillLoadStatus.submitting) return;
    emit(state.copyWith(
      status: TillLoadStatus.submitting,
      clearError: true,
      clearNotice: true,
    ));
    try {
      await _ensureCashSalesSynced();
      final shift = await _repository.open(openingFloatMinor: event.openingFloatMinor);
      final history = await _repository.history();
      emit(TillState(
        status: TillLoadStatus.ready,
        current: shift,
        history: List.unmodifiable(history),
        notice: 'Till opened successfully.',
      ));
    } catch (error) {
      final pending = await _safePendingCount();
      emit(state.copyWith(
        status: TillLoadStatus.failure,
        pendingCashSalesCount: pending,
        errorMessage: _message(error),
        clearNotice: true,
      ));
    }
  }

  Future<void> _onMovement(
    TillCashMovementRecorded event,
    Emitter<TillState> emit,
  ) async {
    if (state.status == TillLoadStatus.submitting) return;
    emit(state.copyWith(
      status: TillLoadStatus.submitting,
      clearError: true,
      clearNotice: true,
    ));
    try {
      await _ensureCashSalesSynced();
      final shift = await _repository.cashMovement(
        movementType: event.movementType,
        amountMinor: event.amountMinor,
        reason: event.reason,
      );
      final history = await _repository.history();
      emit(TillState(
        status: TillLoadStatus.ready,
        current: shift,
        history: List.unmodifiable(history),
        notice: event.movementType == 'paid_in'
            ? 'Cash paid in was recorded.'
            : 'Cash paid out was recorded.',
      ));
    } catch (error) {
      final pending = await _safePendingCount();
      emit(state.copyWith(
        status: TillLoadStatus.failure,
        pendingCashSalesCount: pending,
        errorMessage: _message(error),
        clearNotice: true,
      ));
    }
  }

  Future<void> _onClose(TillClosed event, Emitter<TillState> emit) async {
    if (state.status == TillLoadStatus.submitting) return;
    final current = state.current;
    if (current == null) {
      emit(state.copyWith(
        status: TillLoadStatus.failure,
        errorMessage: 'There is no open till shift to close.',
        clearNotice: true,
      ));
      return;
    }

    emit(state.copyWith(
      status: TillLoadStatus.submitting,
      clearError: true,
      clearNotice: true,
    ));
    try {
      await _ensureCashSalesSynced();
      await _repository.close(
        shiftId: current.id,
        countedCashMinor: event.countedCashMinor,
        note: event.note,
      );
      final history = await _repository.history();
      emit(TillState(
        status: TillLoadStatus.ready,
        history: List.unmodifiable(history),
        notice: 'Till closed and reconciled.',
      ));
    } catch (error) {
      final pending = await _safePendingCount();
      emit(state.copyWith(
        status: TillLoadStatus.failure,
        pendingCashSalesCount: pending,
        errorMessage: _message(error),
        clearNotice: true,
      ));
    }
  }

  Future<void> _ensureCashSalesSynced() async {
    final count = await _repository.pendingCashSalesCount();
    if (count == 0) return;
    throw StateError(
      '$count queued cash sale${count == 1 ? '' : 's'} must sync before changing the till. Sync sales, then refresh this page.',
    );
  }

  Future<int> _safePendingCount() async {
    try {
      return await _repository.pendingCashSalesCount();
    } catch (_) {
      return state.pendingCashSalesCount;
    }
  }

  String _message(Object error) {
    if (error is StateError) return error.message.toString();
    return 'The till operation could not be completed.';
  }
}
