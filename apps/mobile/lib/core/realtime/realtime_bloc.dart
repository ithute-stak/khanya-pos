import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/config/app_config.dart';
import 'package:khanya_pos/core/realtime/realtime_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';

sealed class RealtimeEvent extends Equatable {
  const RealtimeEvent();

  @override
  List<Object?> get props => [];
}

final class RealtimeActivated extends RealtimeEvent {
  const RealtimeActivated();
}

final class RealtimeStopped extends RealtimeEvent {
  const RealtimeStopped();
}

final class RealtimeReconnectNowRequested extends RealtimeEvent {
  const RealtimeReconnectNowRequested();
}

final class _RealtimeMessageReceived extends RealtimeEvent {
  const _RealtimeMessageReceived(this.message);

  final Map<String, dynamic> message;

  @override
  List<Object?> get props => [message];
}

final class _RealtimeConnectionEnded extends RealtimeEvent {
  const _RealtimeConnectionEnded();
}

final class _RealtimeReconnectRequested extends RealtimeEvent {
  const _RealtimeReconnectRequested();
}

enum RealtimeConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class RealtimeState extends Equatable {
  const RealtimeState({
    this.status = RealtimeConnectionStatus.disconnected,
    this.lastEventType,
    this.lastEventAt,
    this.lastEventBranchId,
    this.lastHeartbeatAt,
    this.reconnectAttempt = 0,
    this.eventVersion = 0,
  });

  final RealtimeConnectionStatus status;
  final String? lastEventType;
  final DateTime? lastEventAt;
  final String? lastEventBranchId;
  final DateTime? lastHeartbeatAt;
  final int reconnectAttempt;
  final int eventVersion;

  bool get connected => status == RealtimeConnectionStatus.connected;

  String get statusLabel => switch (status) {
        RealtimeConnectionStatus.disconnected => 'Realtime offline',
        RealtimeConnectionStatus.connecting => 'Connecting realtime…',
        RealtimeConnectionStatus.connected => 'Realtime active',
        RealtimeConnectionStatus.reconnecting => 'Realtime reconnecting',
      };

  RealtimeState copyWith({
    RealtimeConnectionStatus? status,
    String? lastEventType,
    DateTime? lastEventAt,
    String? lastEventBranchId,
    DateTime? lastHeartbeatAt,
    int? reconnectAttempt,
    int? eventVersion,
    bool clearLastEventBranch = false,
  }) {
    return RealtimeState(
      status: status ?? this.status,
      lastEventType: lastEventType ?? this.lastEventType,
      lastEventAt: lastEventAt ?? this.lastEventAt,
      lastEventBranchId:
          clearLastEventBranch ? null : lastEventBranchId ?? this.lastEventBranchId,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      eventVersion: eventVersion ?? this.eventVersion,
    );
  }

  @override
  List<Object?> get props => [
        status,
        lastEventType,
        lastEventAt,
        lastEventBranchId,
        lastHeartbeatAt,
        reconnectAttempt,
        eventVersion,
      ];
}

class RealtimeBloc extends Bloc<RealtimeEvent, RealtimeState> {
  RealtimeBloc({
    required RealtimeClient client,
    required SessionContext sessionContext,
    required ProductRepository productRepository,
    required CustomerRepository customerRepository,
  })  : _client = client,
        _sessionContext = sessionContext,
        _productRepository = productRepository,
        _customerRepository = customerRepository,
        super(const RealtimeState()) {
    on<RealtimeActivated>(_onActivated);
    on<RealtimeStopped>(_onStopped);
    on<RealtimeReconnectNowRequested>(_onReconnectNowRequested);
    on<_RealtimeMessageReceived>(_onMessage);
    on<_RealtimeConnectionEnded>(_onConnectionEnded);
    on<_RealtimeReconnectRequested>(_onReconnectRequested);
  }

  static const _maxReconnectDelay = Duration(seconds: 30);

  final RealtimeClient _client;
  final SessionContext _sessionContext;
  final ProductRepository _productRepository;
  final CustomerRepository _customerRepository;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _reconnectTimer;
  bool _active = false;
  bool _connecting = false;
  int _reconnectAttempt = 0;

  Future<void> _onActivated(
    RealtimeActivated event,
    Emitter<RealtimeState> emit,
  ) async {
    _active = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _connect(emit, reconnecting: false);
  }

  Future<void> _connect(
    Emitter<RealtimeState> emit, {
    required bool reconnecting,
  }) async {
    if (_connecting || !_active) return;

    final tenantId = _sessionContext.tenantId;
    final accessToken = _sessionContext.accessToken;
    if (tenantId == null || accessToken == null) {
      emit(state.copyWith(status: RealtimeConnectionStatus.disconnected));
      return;
    }

    _connecting = true;
    emit(
      state.copyWith(
        status: reconnecting
            ? RealtimeConnectionStatus.reconnecting
            : RealtimeConnectionStatus.connecting,
        reconnectAttempt: _reconnectAttempt,
      ),
    );

    await _subscription?.cancel();
    _subscription = null;
    await _client.close();

    try {
      final stream = _client.connect(
        AppConfig.tenantWebSocketUri(
          tenantId: tenantId,
          accessToken: accessToken,
        ),
      );
      _subscription = stream.listen(
        (message) => add(_RealtimeMessageReceived(message)),
        onError: (_) => add(const _RealtimeConnectionEnded()),
        onDone: () => add(const _RealtimeConnectionEnded()),
        cancelOnError: false,
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: RealtimeConnectionStatus.reconnecting,
          reconnectAttempt: _reconnectAttempt,
        ),
      );
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _onConnectionEnded(
    _RealtimeConnectionEnded event,
    Emitter<RealtimeState> emit,
  ) async {
    if (!_active) return;
    emit(
      state.copyWith(
        status: RealtimeConnectionStatus.reconnecting,
        reconnectAttempt: _reconnectAttempt,
      ),
    );
    _scheduleReconnect();
  }

  Future<void> _onReconnectRequested(
    _RealtimeReconnectRequested event,
    Emitter<RealtimeState> emit,
  ) async {
    _reconnectTimer = null;
    await _connect(emit, reconnecting: true);
  }

  Future<void> _onReconnectNowRequested(
    RealtimeReconnectNowRequested event,
    Emitter<RealtimeState> emit,
  ) async {
    if (!_active) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    await _connect(emit, reconnecting: true);
  }

  void _scheduleReconnect() {
    if (!_active || _reconnectTimer != null || isClosed) return;

    _reconnectAttempt += 1;
    final exponent = (_reconnectAttempt - 1).clamp(0, 4);
    final delaySeconds = 2 * (1 << exponent);
    final delay = Duration(
      seconds: delaySeconds > _maxReconnectDelay.inSeconds
          ? _maxReconnectDelay.inSeconds
          : delaySeconds,
    );

    _reconnectTimer = Timer(delay, () {
      if (!isClosed && _active) {
        add(const _RealtimeReconnectRequested());
      }
    });
  }

  Future<void> _onStopped(
    RealtimeStopped event,
    Emitter<RealtimeState> emit,
  ) async {
    _active = false;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _client.close();
    emit(const RealtimeState());
  }

  Future<void> _onMessage(
    _RealtimeMessageReceived event,
    Emitter<RealtimeState> emit,
  ) async {
    final messageType =
        event.message['event_type']?.toString() ?? event.message['type']?.toString();
    if (messageType == null) return;

    final now = DateTime.now().toUtc();

    if (messageType == 'socket.ready') {
      _reconnectAttempt = 0;
      emit(
        state.copyWith(
          status: RealtimeConnectionStatus.connected,
          reconnectAttempt: 0,
          lastHeartbeatAt: now,
        ),
      );
      return;
    }

    if (messageType == 'pong') {
      emit(
        state.copyWith(
          status: RealtimeConnectionStatus.connected,
          reconnectAttempt: 0,
          lastHeartbeatAt: now,
        ),
      );
      return;
    }

    final eventBranchId = event.message['branch_id']?.toString();
    final currentBranchId = _sessionContext.branchId;
    final branchRelevant =
        eventBranchId == null || currentBranchId == null || eventBranchId == currentBranchId;

    emit(
      state.copyWith(
        status: RealtimeConnectionStatus.connected,
        reconnectAttempt: 0,
        lastEventType: messageType,
        lastEventAt: now,
        lastEventBranchId: eventBranchId,
        clearLastEventBranch: eventBranchId == null,
        eventVersion: state.eventVersion + 1,
      ),
    );

    if (!branchRelevant && _isBranchScoped(messageType)) return;

    if (_refreshesProducts(messageType)) {
      try {
        await _productRepository.refresh();
      } catch (_) {
        // Cached product state remains available until a later refresh succeeds.
      }
    }

    if (_refreshesCustomers(messageType)) {
      try {
        await _customerRepository.refresh();
      } catch (_) {
        // Cached customer state remains available until a later refresh succeeds.
      }
    }
  }

  bool _isBranchScoped(String eventType) =>
      eventType.startsWith('inventory.') ||
      eventType.startsWith('sale.') ||
      eventType.startsWith('purchase.') ||
      eventType.startsWith('expense.') ||
      eventType.startsWith('till.');

  bool _refreshesProducts(String eventType) =>
      eventType.startsWith('inventory.') ||
      eventType.startsWith('product.') ||
      eventType.startsWith('sale.') ||
      eventType.startsWith('purchase.');

  bool _refreshesCustomers(String eventType) =>
      eventType.startsWith('customer.') ||
      eventType.startsWith('sale.') ||
      eventType.startsWith('payment.');

  @override
  Future<void> close() async {
    _active = false;
    _reconnectTimer?.cancel();
    await _subscription?.cancel();
    await _client.close();
    return super.close();
  }
}
