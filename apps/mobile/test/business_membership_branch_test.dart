import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';

void main() {
  test('business membership keeps named branch metadata and labels', () {
    final membership = BusinessMembership.fromJson({
      'tenant_id': 'tenant-1',
      'tenant_name': 'Test Business',
      'tenant_slug': 'test-business',
      'role': 'owner',
      'branch_ids': ['branch-main', 'branch-east'],
      'branches': [
        {
          'id': 'branch-main',
          'name': 'Main Store',
          'code': 'MAIN',
          'location': 'Maseru',
          'is_main': true,
          'is_active': true,
        },
        {
          'id': 'branch-east',
          'name': 'East Branch',
          'code': 'EAST',
          'location': 'Mafeteng',
          'is_main': false,
          'is_active': true,
        },
      ],
    });

    expect(membership.branchIds, ['branch-main', 'branch-east']);
    expect(membership.branches, hasLength(2));
    expect(membership.branchById('branch-main')?.name, 'Main Store');
    expect(membership.branchLabel('branch-main'), 'Main Store (MAIN)');
    expect(membership.branchLabel('branch-east'), 'East Branch (EAST)');

    final restored = BusinessMembership.fromJson(membership.toJson());
    expect(restored, membership);
  });

  test('old saved sessions without branch metadata remain compatible', () {
    final membership = BusinessMembership.fromJson({
      'tenant_id': 'tenant-1',
      'tenant_name': 'Legacy Business',
      'tenant_slug': 'legacy-business',
      'role': 'cashier',
      'branch_ids': ['legacy-branch'],
    });

    expect(membership.branches, isEmpty);
    expect(
      membership.branchLabel('legacy-branch', fallbackIndex: 0),
      'Branch 1',
    );
  });
}
