import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

void main() {
  const session = AuthSession(
    userId: 'user-1',
    displayName: 'Thabo Mokoena',
    email: 'thabo@khanya.co.ls',
    accessToken: 'access',
    refreshToken: 'refresh',
    memberships: [
      BusinessMembership(
        tenantId: 'tenant-1',
        tenantName: 'Mokoena General Dealer',
        tenantSlug: 'mokoena-general-dealer',
        role: 'owner',
        branchIds: ['branch-1'],
      ),
    ],
  );

  test('business selection updates authenticated session context', () async {
    final bloc = SessionBloc();
    bloc.add(const SessionSignedIn(session));
    await Future<void>.delayed(Duration.zero);
    bloc.add(const SessionBusinessSelected(tenantId: 'tenant-1', branchId: 'branch-1'));
    await Future<void>.delayed(Duration.zero);

    final state = bloc.state as SessionAuthenticated;
    expect(state.session.selectedTenantId, 'tenant-1');
    expect(state.session.selectedBranchId, 'branch-1');
    expect(state.session.requestHeaders['X-Tenant-ID'], 'tenant-1');
    await bloc.close();
  });

  test('session invalidation immediately returns UI state to signed out', () async {
    final sessionContext = SessionContext();
    final bloc = SessionBloc(sessionContext: sessionContext);
    bloc.add(const SessionSignedIn(session));
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state, isA<SessionAuthenticated>());

    sessionContext.invalidate();
    await Future<void>.delayed(Duration.zero);
    expect(bloc.state, isA<SessionUnauthenticated>());

    await bloc.close();
    await sessionContext.close();
  });
}
