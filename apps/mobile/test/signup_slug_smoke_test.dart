import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/auth/presentation/signup_page.dart';

void main() {
  testWidgets('signup page can be constructed', (tester) async {
    const page = SignupPage(onBackToSignIn: _noop);
    expect(page, isA<SignupPage>());
  });

  testWidgets('manual slug deletions are not restored by business name edits', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SignupPage(onBackToSignIn: _noop)),
    );

    final business = find.widgetWithText(TextFormField, 'Business name');
    final slug = find.widgetWithText(TextFormField, 'Business ID / slug');

    await tester.enterText(business, 'Khanya Retail');
    await tester.pump();
    TextFormField slugField = tester.widget(slug);
    expect(slugField.controller!.text, 'khanya-retail');

    // A cleared field must remain cleared while the user is correcting it.
    await tester.enterText(slug, '');
    await tester.pump();
    await tester.enterText(business, 'Khanya Retail Ltd');
    await tester.pump();
    slugField = tester.widget(slug);
    expect(slugField.controller!.text, '');

    // Replacing the deleted text must not resurrect the old suggestion.
    await tester.enterText(slug, 'my-shop');
    await tester.pump();
    await tester.enterText(business, 'Khanya Retail Limited');
    await tester.pump();
    slugField = tester.widget(slug);
    expect(slugField.controller!.text, 'my-shop');
  });
}

void _noop() {}
