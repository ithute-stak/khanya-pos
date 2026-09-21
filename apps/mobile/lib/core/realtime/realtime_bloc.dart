import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/config/app_config.dart';
import 'package:khanya_pos/core/realtime/realtime_client.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';

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

final class _RealtimeMessageReceived extends RealtimeEvent {
  const _RealtimeMessageReceived(this.message);
  final Map<String, dynamic> message;
  @override
  List<Object?> get props => [message];
}

final class _RealtimeConnectionEnded extends RealtimeEvent {
  const _RealtimeConnectionEnded();
}

class RealtimeState extends Equatable {
  const RealtimeState({this.connected = false, this.lastEventType});
  final bool connected;
  final String? lastEventType;
  @override
  List<Object?> get props => [connected, lastEventType];
}

class RealtimeBloc extends Bloc<RealtimeEvent, RealtimeState> {
  RealtimeBloc({
    required RealtimeClient client,
    required SessionContext sessionContext,
    required ProductRepository productRepository,
  })  : _client = client,
        _sessionContext = sessionContext,
        _productRepository = productRepository,
        super(const RealtimeState()) {
    on<RealtimeActivated>(_onActivated);
    on<RealtimeStopped>(_onStopped);
    on<_RealtimeMessageReceived>(_onMessage);
    on<_RealtimeConnectionEnded>((event, emit) => emit(RealtimeState(lastEventType: state.lastEventType)));
  }

  final RealtimeClient _client;
  final SessionContext _sessionContext;
  final ProductRepository _productRepository;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  Future<void> _onActivated(RealtimeActivated event, Emitter<RealtimeState> emit) async {
    final tenantId = _sessionContext.tenantId;
    final accessToken = _sessionContext.accessToken;
    if (tenantId == null || accessToken == null) return;
    await _subscription?.cancel();
    await _client.close();
    try {
      final stream = _client.connect(
        AppConfig.tenantWebSocketUri(tenantId: tenantId, accessToken: accessToken),
      );
      _subscription = stream.listen(
        (message) => add(_RealtimeMessageReceived(message)),
        onError: (_) => add(const _RealtimeConnectionEnded()),
        onDone: () => add(const _RealtimeConnectionEnded()),
      );
      emit(RealtimeState(connected: true, lastEventType: state.lastEventType));
    } catch (_) {
      emit(RealtimeState(lastEventType: state.lastEventType));
    }
  }

  Future<void> _onStopped(RealtimeStopped event, Emitter<RealtimeState> emit) async {
    await _subscription?.cancel();
    _subscription = null;
    await _client.close();
    emit(const RealtimeState());
  }

  Future<void> _onMessage(
    _RealtimeMessageReceived event,
    Emitter<RealtimeState> emit,
  ) async {
    final eventType = event.message['event_type']?.toString() ?? event.message['type']?.toString();
    emit(RealtimeState(connected: true, lastEventType: eventType));
    if (eventType == null) return;
    if (eventType.startsWith('inventory.') ||
        eventType.startsWith('product.') ||
        eventType.startsWith('sale.')) {
      try {
        await _productRepository.refresh();
      } catch (_) {
        // Cached state remains authoritative for the UI until the next successful refresh.
      }
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _client.close();
    return super.close();
  }
}
