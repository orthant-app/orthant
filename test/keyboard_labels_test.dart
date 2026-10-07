import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/permission/ready_screen.dart';
import 'package:orthant/settings/keyboard_labels.dart';
import 'package:orthant/settings/mac_theme.dart';
import 'package:orthant/settings/region_picker_sheet.dart';

import 'support/carbon_terms.dart';

void main() {
  testWidgets('onboarding keycaps follow a layout change while visible', (tester) async {
    final labels = ValueNotifier<Map<int, String>>(labelsByCarbon(const {31: 'R'}));
    addTearDown(labels.dispose);
    await tester.pumpWidget(ValueListenableBuilder(
      valueListenable: labels,
      builder: (_, value, child) => KeyboardLabels(labels: value, child: child!),
      child: MaterialApp(
        theme: macTheme(Brightness.light),
        home: ReadyScreen(bindings: macDefaults, onDone: () {},
            onOpenShortcuts: () {}),
      ),
    ));
    expect(find.text('R'), findsOneWidget);
    expect(find.text('O'), findsNothing);
    labels.value = labelsByCarbon(const {31: 'О'});
    await tester.pump();
    expect(find.text('О'), findsOneWidget);
    expect(find.text('R'), findsNothing);
  });

  testWidgets('an open picker updates both visible and spoken shortcut labels', (tester) async {
    final semantics = tester.ensureSemantics();
    final labels = ValueNotifier<Map<int, String>>(labelsByCarbon(const {31: 'R'}));
    addTearDown(labels.dispose);
    await tester.pumpWidget(ValueListenableBuilder(
      valueListenable: labels,
      builder: (_, value, child) => KeyboardLabels(labels: value, child: child!),
      child: MaterialApp(
        theme: macTheme(Brightness.light),
        home: Builder(builder: (context) => TextButton(
          onPressed: () => showDialog<void>(context: context, builder: (_) =>
            RegionPickerSheet(gridCols: 6, gridRows: 6,
              initialChord: carbon(31, kControlOption),
              onSubmit: (_) {}, onCancel: () => Navigator.pop(context))),
          child: const Text('Open picker'),
        )),
      ),
    ));
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(find.text('R'), findsOneWidget);
    expect(find.bySemanticsLabel('Record shortcut, currently ⌃⌥R'), findsOneWidget);
    labels.value = labelsByCarbon(const {31: 'О'});
    await tester.pump();
    expect(find.text('О'), findsOneWidget);
    expect(find.bySemanticsLabel('Record shortcut, currently ⌃⌥О'), findsOneWidget);
    expect(find.text('R'), findsNothing);
    semantics.dispose();
  });
}
