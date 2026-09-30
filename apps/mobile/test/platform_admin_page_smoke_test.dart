import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/platform/presentation/platform_admin_page.dart';

void main() {
  testWidgets('platform admin page can be constructed', (tester) async {
    const page = PlatformAdminPage();
    expect(page, isA<PlatformAdminPage>());
  });
}
