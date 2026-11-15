import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/purchasing/presentation/new_purchase_page.dart';

void main() {
  testWidgets('payment text preserves deletions and partial decimals across rebuilds', (tester) async {
    int amountMinor = 1200;
    late StateSetter rebuild;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return PurchasePaymentAmount(
              amountPaidMinor: amountMinor,
              enabled: true,
              onChanged: (_) {},
            );
          },
        ),
      ),
    ));

    final field = find.byType(TextFormField);
    await tester.enterText(field, '12.');
    await tester.pump();
    rebuild(() => amountMinor = 1200); // BLoC normalizes to 12.00
    await tester.pump();
    expect(tester.widget<TextFormField>(field).controller!.text, '12.');

    await tester.enterText(field, '');
    await tester.pump();
    rebuild(() => amountMinor = 0);
    await tester.pump();
    expect(tester.widget<TextFormField>(field).controller!.text, '');

    await tester.enterText(field, '9.5');
    await tester.pump();
    rebuild(() => amountMinor = 950);
    await tester.pump();
    expect(tester.widget<TextFormField>(field).controller!.text, '9.5');
  });

  testWidgets('supplier credit deliberately clears the payment field', (tester) async {
    bool enabled = true;
    int amountMinor = 1250;
    late StateSetter rebuild;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          rebuild = setState;
          return PurchasePaymentAmount(
            amountPaidMinor: amountMinor,
            enabled: enabled,
            onChanged: (_) {},
          );
        }),
      ),
    ));
    final field = find.byType(TextFormField);
    await tester.enterText(field, '12.5');
    rebuild(() {
      enabled = false;
      amountMinor = 0;
    });
    await tester.pump();
    expect(tester.widget<TextFormField>(field).controller!.text, '0.00');
  });
}
