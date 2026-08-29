import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/settings/general_pane.dart';
import 'package:orthant/settings/grid_preview.dart';
import 'package:orthant/settings/mac_stepper.dart';
import 'package:orthant/settings/mac_theme.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/shortcuts/bindings.dart';

void main() {
  late List<Settings> changes;

  Widget host(Settings settings) {
    changes = [];
    return MaterialApp(
      theme: macTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          width: 560,
          child: GeneralPane(
            settings: settings,
            onSettingsChanged: changes.add,
            permissionGranted: true,
            loginStatus: LoginItemStatus.disabled,
            bindings: kDefaultBindings,
          ),
        ),
      ),
    );
  }

  /// The stepper for [caption]'s row — the pane has three, so find by label.
  Finder stepperFor(String caption) => find.ancestor(
        of: find.text(caption),
        matching: find.byType(Row),
      ).first;

  Future<void> bump(WidgetTester tester, String caption, {required bool up}) async {
    final row = stepperFor(caption);
    final arrow = find.descendant(
      of: row,
      matching: find.byIcon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down),
    );
    await tester.tap(arrow);
    await tester.pumpAndSettle();
  }

  testWidgets('the column stepper changes only the columns', (tester) async {
    await tester.pumpWidget(host(const Settings()));
    await bump(tester, 'Columns', up: true);
    expect(changes.single, const Settings().copyWith(gridCols: 7));
  });

  testWidgets('the row stepper changes only the rows', (tester) async {
    await tester.pumpWidget(host(const Settings()));
    await bump(tester, 'Rows', up: false);
    expect(changes.single, const Settings().copyWith(gridRows: 5));
  });

  testWidgets('steppers disable at the bounds rather than clamping silently',
      (tester) async {
    // The limit should be visible before it is hit — a button that does
    // nothing when pressed reads as a broken control.
    await tester.pumpWidget(host(
        const Settings(gridCols: kMaxGridAxis, gridRows: kMinGridAxis)));
    await bump(tester, 'Columns', up: true);
    await bump(tester, 'Rows', up: false);
    expect(changes, isEmpty);
  });

  testWidgets('the gap size survives gaps being switched off', (tester) async {
    // Disabled, not hidden, and the value is untouched: switching gaps back on
    // must return what the user picked rather than a default.
    await tester.pumpWidget(host(const Settings(gaps: false, gapSize: 12)));
    expect(find.text('12'), findsOneWidget);

    final stepper = tester.widget<MacStepper>(find.descendant(
      of: stepperFor('Size'),
      matching: find.byType(MacStepper),
    ));
    expect(stepper.enabled, isFalse);
  });

  testWidgets('toggling gaps reports only the toggle', (tester) async {
    await tester.pumpWidget(host(const Settings(gapSize: 12)));
    await tester.tap(find.text('Leave gaps'));
    await tester.pumpAndSettle();
    expect(changes.single, const Settings(gaps: true, gapSize: 12));
  });

  testWidgets('the preview shows the live grid and the *effective* gap',
      (tester) async {
    // effectiveGap, not gapSize. The picture has to show what a placement
    // would actually do, and with gaps off that is no gap at all.
    await tester.pumpWidget(host(const Settings(
        gridCols: 8, gridRows: 3, gaps: false, gapSize: 16)));
    var preview = tester.widget<GridPreview>(find.byType(GridPreview));
    expect(preview.cols, 8);
    expect(preview.rows, 3);
    expect(preview.gap, 0);

    await tester.pumpWidget(host(const Settings(
        gridCols: 8, gridRows: 3, gaps: true, gapSize: 16)));
    preview = tester.widget<GridPreview>(find.byType(GridPreview));
    expect(preview.gap, 16);
  });

  testWidgets('the caption reads the gap only when it is in force',
      (tester) async {
    await tester.pumpWidget(host(const Settings(gaps: true, gapSize: 8)));
    expect(find.text('6 × 6 · up to 8 pt gaps'), findsOneWidget);

    await tester.pumpWidget(host(const Settings(gaps: false, gapSize: 8)));
    expect(find.text('6 × 6'), findsOneWidget);
  });
}
