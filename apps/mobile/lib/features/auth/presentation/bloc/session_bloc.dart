import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';

sealed class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

final class SessionStarted extends SessionEvent {
  const SessionStarted();
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

sealed class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => [];
}

final class SessionInitial extends SessionState {
  const SessionInitial();
}

final class SessionUnauthenticated extends SessionState {
  const SessionUnauthenticated();
}

final class SessionAuthenticated extends SessionState {
  const SessionAuthenticated(this.session);
  final AuthSession session;

  @override
  List<Object?> get props => [session];
}

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc() : super(const SessionInitial()) {
    on<SessionStarted>((event, emit) => emit(const SessionUnauthenticated()));
    on<SessionSignedIn>((event, emit) => emit(SessionAuthenticated(event.session)));
    on<SessionBusinessSelected>((event, emit) {
      final current = state;
      if (current is! SessionAuthenticated) return;
      final membershipExists = current.session.memberships.any(
        (membership) => membership.tenantId == event.tenantId,
      );
      if (!membershipExists) return;
      emit(
        SessionAuthenticated(
          current.session.selectBusiness(
            tenantId: event.tenantId,
            branchId: event.branchId,
          ),
        ),
      );
    });
    on<SessionSignedOut>((event, emit) => emit(const SessionUnauthenticated()));
  }
}
