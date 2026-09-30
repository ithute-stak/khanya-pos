import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';

void main() {
  test('platform admin capability survives profile serialization', () {
    const session = AuthSession(
      userId: 'user-1',
      displayName: 'System Owner',
      email: 'owner@example.com',
      accessToken: 'access',
      refreshToken: 'refresh',
      memberships: [],
      isPlatformAdmin: true,
    );

    final restored = AuthSession.fromProfileJson(
      session.toProfileJson(),
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );

    expect(restored.isPlatformAdmin, isTrue);
    expect(restored.memberships, isEmpty);
    expect(restored.selectedTenantId, isNull);
  });
}
