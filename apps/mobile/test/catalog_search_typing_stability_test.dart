import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/catalog/presentation/products_page.dart';

void main() {
  testWidgets('catalog search keeps deletions and cursor through layout changes', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final edits = <String>[];

    Widget layout({required bool compact}) => MaterialApp(
      home: Scaffold(
        body: compact
            ? Column(children: [
                CatalogSearchInput(controller: controller, onChanged: edits.add),
              ])
            : Row(children: [
                Expanded(
                  child: CatalogSearchInput(
                    controller: controller,
                    onChanged: edits.add,
                  ),
                ),
              ]),
      ),
    );

    await tester.pumpWidget(layout(compact: true));
    await tester.enterText(find.byType(TextField), 'khanya');
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'kha');
    await tester.pump();

    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pumpWidget(layout(compact: false));
    await tester.pump();

    expect(controller.text, 'kha');
    expect(controller.selection.baseOffset, 2);

    await tester.enterText(find.byType(TextField), 'khali');
    await tester.pump();
    await tester.pumpWidget(layout(compact: true));
    await tester.pump();

    expect(controller.text, 'khali');
    expect(edits, ['khanya', 'kha', 'khali']);
  });
}
