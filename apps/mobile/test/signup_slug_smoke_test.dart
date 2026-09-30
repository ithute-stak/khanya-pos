import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/auth/presentation/signup_page.dart';

void main() {
  testWidgets('signup page can be constructed', (tester) async {
    const page = SignupPage(onBackToSignIn: _noop);
    expect(page, isA<SignupPage>());
  });
}

void _noop() {}
