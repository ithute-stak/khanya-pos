import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/features/auth/data/auth_repository.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';

sealed class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

final class SessionStarted extends SessionEvent {
  const SessionStarted();
}

final class SessionLoginRequested extends SessionEvent {
  const SessionLoginRequested({required this.identifier, required this.password});
  final String identifier;
  final String password;

  @override
  List<Object?> get props => [identifier, password];
}

final class SessionSignedIn extends SessionEvent {
  const SessionSignedIn(this.session);
  final AuthSession session;

  @override
  List<Object?> get props => [session];
}

final class SessionBusinessSelected extends SessionEvent {
  const SessionBusinessSelected({required this.tenantId, this.branchId});
  final String tenantId;
  final String? branchId;

  @override
  List<Object?> get props => [tenantId, branchId];
}

final class SessionSignedOut extends SessionEvent {
  const SessionSignedOut();
}

final class SessionInvalidated extends SessionEvent {
  const SessionInvalidated();
}

sealed class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => [];
}

final class SessionInitial extends SessionState {
  const SessionInitial();
}

final class SessionRestoring extends SessionState {
  const SessionRestoring();
}

final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

final class SessionAuthenticating extends SessionState {
  const SessionAuthenticating();
}

final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.session);
  final AuthSession session;

  @override
  List<Object?> get props => [session];
}

final class SessionFailure extends SessionState {
  const SessionFailure(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc({AuthRepository? authRepository, SessionContext? sessionContext})
      : _authRepository = authRepository,
        _sessionContext = sessionContext,
        super(const SessionInitial()) {
    on<SessionStarted>(_onStarted);
    on<SessionLoginRequested>(_onLoginRequested);
    on<SessionSignedIn>(_onSignedIn);
    on<SessionBusinessSelected>(_onBusinessSelected);
    on<SessionSignedOut>(_onSignedOut);
    on<SessionInvalidated>((event, emit) => emit(const SessionUnauthenticated()));
    _invalidationSubscription = sessionContext?.invalidations.listen(
      (_) => add(const SessionInvalidated()),
    );
  }

  final AuthRepository? _authRepository;
  final SessionContext? _sessionContext;
  StreamSubscription<void>? _invalidationSubscription;

  Future<void> _onStarted(SessionStarted event, Emitter<SessionState> emit) async {
    final repository = _authRepository;
    if (repository == null) {
      emit(const SessionUnauthenticated());
      return;
    }
    emit(const SessionRestoring());
    try {
      final session = await repository.restore();
      if (session == null) {
        emit(const SessionUnauthenticated());
        return;
      }
      _applyContext(session);
      emit(SessionAuthenticated(session));
    } catch (_) {
      await repository.clearLocalSession();
      emit(const SessionUnauthenticated());
    }
  }

  Future<void> _onLoginRequested(
    SessionLoginRequested event,
    Emitter<SessionState> emit,
  ) async {
    final repository = _authRepository;
    if (repository == null) {
      emit(const SessionFailure('Authentication is not configured.'));
      return;
    }
    emit(const SessionAuthenticating());
    try {
      final session = await repository.login(
        identifier: event.identifier,
        password: event.password,
      );
      _applyContext(session);
      emit(SessionAuthenticated(session));
    } catch (error) {
      emit(SessionFailure(_loginError(error)));
    }
  }

  Future<void> _onSignedIn(SessionSignedIn event, Emitter<SessionState> emit) async {
    _applyContext(event.session);
    await _authRepository?.rememberSession(event.session);
    emit(SessionAuthenticated(event.session));
  }

  Future<void> _onBusinessSelected(
    SessionBusinessSelected event,
    Emitter<SessionState> emit,
  ) async {
    final current = state;
    if (current is! SessionAuthenticated) return;
    final membership = current.session.memberships
        .where((item) => item.tenantId == event.tenantId)
        .firstOrNull;
    if (membership == null) return;
    if (event.branchId != null && !membership.branchIds.contains(event.branchId)) return;
    final updated = current.session.selectBusiness(
      tenantId: event.tenantId,
      branchId: event.branchId,
    );
    _sessionContext?.selectBusiness(tenantId: event.tenantId, branchId: event.branchId);
    await _authRepository?.rememberSession(updated);
    emit(SessionAuthenticated(updated));
  }

  Future<void> _onSignedOut(SessionSignedOut event, Emitter<SessionState> emit) async {
    await _authRepository?.logout();
    _sessionContext?.clear();
    emit(const SessionUnauthenticated());
  }

  void _applyContext(AuthSession session) {
    _sessionContext?.apply(
      accessToken: session.accessToken,
      tenantId: session.selectedTenantId,
      branchId: session.selectedBranchId,
    );
  }

  String _loginError(Object error) {
    if (error is DioException) {
      final detail = error.response?.data;
      if (detail is Map<String, dynamic> && detail['detail'] != null) {
        return detail['detail'].toString();
      }
      if (error.response == null) {
        return 'Cannot reach the Khanya server. Check your connection and try again.';
      }
    }
    return 'Sign in failed. Please check your details and try again.';
  }

  @override
  Future<void> close() async {
    await _invalidationSubscription?.cancel();
    return super.close();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
