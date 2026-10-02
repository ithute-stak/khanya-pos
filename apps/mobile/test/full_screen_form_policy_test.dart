import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily POS and platform data-entry flows stay full-screen', () {
    final till = File('lib/features/pos/presentation/till_page.dart').readAsStringSync();
    final platform = File(
      'lib/features/platform/presentation/platform_admin_page.dart',
    ).readAsStringSync();
    final pos = File('lib/features/pos/presentation/pos_page.dart').readAsStringSync();

    expect(
      till,
      isNot(contains('showDialog<')),
      reason: 'Till data-entry forms must use dedicated screens.',
    );
    expect(
      till,
      isNot(contains('AlertDialog(')),
      reason: 'Till data-entry forms must use dedicated screens.',
    );
    expect(
      platform,
      isNot(contains('showDialog<')),
      reason: 'Platform admin data-entry forms must use dedicated screens.',
    );
    expect(
      platform,
      isNot(contains('AlertDialog(')),
      reason: 'Platform admin data-entry forms must use dedicated screens.',
    );
    expect(
      pos,
      isNot(contains('showModalBottomSheet')),
      reason: 'Mobile checkout must remain a full-screen flow.',
    );
  });
}
