import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/settings/data/business_settings_repository.dart';

void main() {
  test('managed branch parses main and active state', () {
    final branch = ManagedBranch.fromJson({
      'id': 'branch-1',
      'name': 'Maseru Central',
      'code': 'MSU',
      'location': 'Maseru',
      'is_main': true,
      'is_active': true,
    });

    expect(branch.name, 'Maseru Central');
    expect(branch.isMain, isTrue);
    expect(branch.isActive, isTrue);
  });

  test('business settings parse identity', () {
    final business = BusinessSettings.fromJson({
      'id': 'tenant-1',
      'name': 'Khanya Resources Pty Ltd',
      'slug': 'khanya-resources',
      'is_active': true,
    });

    expect(business.slug, 'khanya-resources');
    expect(business.isActive, isTrue);
  });
}
