import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

void main() {
  test('business selection updates authenticated session context', () async {
    final bloc = SessionBloc();
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
}
