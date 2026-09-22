import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/staff/domain/staff_member.dart';

void main() {
  test('StaffMember parses role status and branch access', () {
    final member = StaffMember.fromJson({
      'membership_id': 'membership-1',
      'user_id': 'user-1',
      'display_name': 'Mpho Cashier',
      'email': 'mpho@example.com',
      'phone': '+26658000000',
      'role': 'cashier',
      'is_active': true,
      'branch_ids': ['branch-1', 'branch-2'],
    });

    expect(member.membershipId, 'membership-1');
    expect(member.role, 'cashier');
    expect(member.isActive, isTrue);
    expect(member.branchIds, ['branch-1', 'branch-2']);
  });

  test('StaffBranch parses branch identity', () {
    final branch = StaffBranch.fromJson({
      'id': 'branch-1',
      'name': 'Main Shop',
      'code': 'MAIN',
      'location': 'Maseru',
      'is_main': true,
    });

    expect(branch.name, 'Main Shop');
    expect(branch.code, 'MAIN');
    expect(branch.isMain, isTrue);
  });
}
