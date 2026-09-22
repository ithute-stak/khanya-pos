import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/devices/data/device_repository.dart';

void main() {
  test('managed device parses workstation status and version', () {
    final device = ManagedDevice.fromJson({
      'id': 'd1',
      'installation_id': 'install-12345678',
      'branch_id': 'b1',
      'branch_name': 'Maseru Main',
      'name': 'Front Till',
      'device_type': 'pos',
      'platform': 'windows',
      'app_version': '1.0.0',
      'is_active': true,
      'last_seen_at': '2026-09-22T07:45:00Z',
    });

    expect(device.name, 'Front Till');
    expect(device.branchName, 'Maseru Main');
    expect(device.appVersion, '1.0.0');
    expect(device.isActive, isTrue);
    expect(device.lastSeenAt, isNotNull);
  });
}
