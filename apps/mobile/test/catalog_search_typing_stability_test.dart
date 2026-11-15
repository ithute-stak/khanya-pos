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
  testWidgets('IME delete and retype keeps exact field value after rebuild', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final edits = <String>[];
    late StateSetter rebuild;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return CatalogSearchInput(
              controller: controller,
              onChanged: edits.add,
            );
          },
        ),
      ),
    ));
    await tester.showKeyboard(find.byType(TextField));

    // Simulate the editing values delivered by a platform keyboard.
    void sendEdit(String text) {
      tester.testTextInput.updateEditingValue(TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ));
    }

    sendEdit('khanya');
    await tester.pump();
    sendEdit('khan');
    await tester.pump();
    rebuild(() {});
    await tester.pump();
    expect(controller.text, 'khan');
    expect(controller.selection.baseOffset, 4);

    sendEdit('');
    await tester.pump();
    rebuild(() {});
    await tester.pump();
    expect(controller.text, '');

    sendEdit('shop');
    await tester.pump();
    rebuild(() {});
    await tester.pump();
    expect(controller.text, 'shop');
    expect(controller.selection.baseOffset, 4);
    expect(edits, ['khanya', 'khan', '', 'shop']);
  });

}
