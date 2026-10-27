import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/settings/mac_popup_button.dart';
import 'package:orthant/settings/platform_theme.dart';

/// The pop-up button, by itself. The Language picker is its first user, so the
/// entries here are that picker's: a null value (System) is as real a choice
/// as a tag, which is why the type is `String?` and not `String`.
void main() {
  const items = <(String?, String)>[
    (null, 'System'),
    ('en', 'English'),
    ('zh-Hans', '简体中文'),
    ('zh-Hant', '繁體中文'),
  ];

  late List<String?> chosen;

  /// [chosen] cannot say "not called" with a null entry in it, so a call is
  /// counted by its length: a null pick is `[null]`, no pick is `[]`.
  Widget host({
    String? value,
    bool enabled = true,
    String? semanticLabel = 'Language',
  }) {
    chosen = [];
    return MaterialApp(
      theme: orthantTheme(Brightness.light),
      home: Scaffold(
        body: Center(
          child: MacPopUpButton<String?>(
            value: value,
            items: items,
            tokens: PlatformTokens.macLight,
            semanticLabel: semanticLabel,
            onChanged: enabled ? chosen.add : null,
          ),
        ),
      ),
    );
  }

  /// The entries of the open menu, top to bottom.
  List<String> menuEntries(WidgetTester tester) {
    final found = <(double, String)>[
      for (final (_, name) in items)
        for (final e in find.widgetWithText(MenuItemButton, name).evaluate())
          (tester.getTopLeft(find.byElementPredicate((x) => x == e)).dy, name),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, name) in found) name];
  }

  /// Whether the focused node is part of the pop-up button's own tree, the
  /// button or one of its entries, and not something else on the screen.
  bool focusIsInsidePopUp(WidgetTester tester) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return find
        .descendant(
          of: find.byType(MacPopUpButton<String?>),
          matching: find.byElementPredicate((e) => e == context),
        )
        .evaluate()
        .isNotEmpty;
  }

  /// The label of the entry holding the keyboard focus, or null when focus is
  /// on the button (a MenuItemButton is the only focusable text in the menu).
  String? focusedEntry(WidgetTester tester) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    for (final (_, name) in items) {
      final entry = find.widgetWithText(MenuItemButton, name);
      if (find
          .descendant(
              of: entry, matching: find.byElementPredicate((e) => e == context))
          .evaluate()
          .isNotEmpty) {
        return name;
      }
    }
    return null;
  }

  Future<void> openByTap(WidgetTester tester) async {
    await tester.tap(find.byType(MacPopUpButton<String?>));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the selected entry, and the others only once opened',
      (tester) async {
    await tester.pumpWidget(host(value: 'zh-Hans'));
    expect(find.text('简体中文'), findsOneWidget);
    for (final other in ['System', 'English', '繁體中文']) {
      expect(find.text(other), findsNothing, reason: '$other is not selected');
    }
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('a null value is an entry like any other', (tester) async {
    await tester.pumpWidget(host(value: null));
    expect(find.text('System'), findsOneWidget);
  });

  testWidgets('a tap opens the menu with every entry, in the order given',
      (tester) async {
    await tester.pumpWidget(host(value: 'en'));
    await openByTap(tester);
    expect(menuEntries(tester), ['System', 'English', '简体中文', '繁體中文']);
  });

  testWidgets('a second tap on the button closes the menu again',
      (tester) async {
    await tester.pumpWidget(host(value: 'en'));
    await openByTap(tester);
    expect(find.byType(MenuItemButton), findsNWidgets(4));
    await tester.tap(find.byType(MacPopUpButton<String?>));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(chosen, isEmpty);
  });

  testWidgets('a pick reports its value, once, and closes the menu',
      (tester) async {
    await tester.pumpWidget(host(value: 'en'));
    await openByTap(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, '繁體中文'));
    await tester.pumpAndSettle();
    expect(chosen, ['zh-Hant']);
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('the null entry reports null, not nothing', (tester) async {
    await tester.pumpWidget(host(value: 'en'));
    await openByTap(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, 'System'));
    await tester.pumpAndSettle();
    expect(chosen, [null]);
  });

  testWidgets('picking what is already selected reports nothing but closes',
      (tester) async {
    // A stored Hong Kong choice is shown as the Traditional entry; the pane
    // relies on this so that choosing that entry again cannot flatten it.
    await tester.pumpWidget(host(value: 'zh-Hant'));
    await openByTap(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, '繁體中文'));
    await tester.pumpAndSettle();
    expect(chosen, isEmpty);
    expect(find.byType(MenuItemButton), findsNothing);
  });

  testWidgets('with no callback it is inert: no menu, no focus',
      (tester) async {
    await tester.pumpWidget(host(value: 'en', enabled: false));
    await tester.tap(find.byType(MacPopUpButton<String?>));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusIsInsidePopUp(tester), isFalse);
  });

  group('by keyboard', () {
    testWidgets('Tab reaches it, Space opens it on the selected entry, the '
        'arrows move and Return chooses', (tester) async {
      await tester.pumpWidget(host(value: 'en'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(focusIsInsidePopUp(tester), isTrue,
          reason: 'Tab did not land on the button');
      expect(find.byType(MenuItemButton), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(menuEntries(tester), hasLength(4));
      expect(focusedEntry(tester), 'English',
          reason: 'opens on what is selected, as a macOS pop-up does');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedEntry(tester), '简体中文');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedEntry(tester), '繁體中文');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focusedEntry(tester), '简体中文');
      expect(chosen, isEmpty, reason: 'moving is not choosing');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(chosen, ['zh-Hans']);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(focusIsInsidePopUp(tester), isTrue,
          reason: 'focus must come back to the button, not be lost');
      expect(focusedEntry(tester), isNull);
    });

    testWidgets('Return opens it too', (tester) async {
      await tester.pumpWidget(host(value: null));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(focusedEntry(tester), 'System');
    });

    testWidgets('Space chooses the focused entry as well', (tester) async {
      await tester.pumpWidget(host(value: 'en'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(chosen, [null]);
    });

    testWidgets('Esc closes it without choosing and hands focus back',
        (tester) async {
      await tester.pumpWidget(host(value: 'en'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(chosen, isEmpty);
      expect(find.byType(MenuItemButton), findsNothing);
      expect(focusIsInsidePopUp(tester), isTrue);
      expect(focusedEntry(tester), isNull);
    });

    testWidgets('it can be opened again after a choice', (tester) async {
      await tester.pumpWidget(host(value: 'en'));
      for (var i = 0; i < 2; i++) {
        await openByTap(tester);
        expect(menuEntries(tester), hasLength(4), reason: 'open #$i');
        await tester.tap(find.widgetWithText(MenuItemButton, 'System'));
        await tester.pumpAndSettle();
      }
      expect(chosen, [null, null]);
    });
  });

  group('what a screen reader gets', () {
    testWidgets('a button with a name, the selection and a tap action',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(value: 'zh-Hans'));

      final node = find.semantics.byLabel('Language').evaluate().single;
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue,
          reason: 'hearing a control is not operating one');
      expect(data.value, '简体中文');
      handle.dispose();
    });

    testWidgets('without a name it reads the selected entry', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(value: 'en', semanticLabel: null));
      final node = find.semantics.byLabel('English').evaluate().single;
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('the tap action opens the menu, and an entry\'s action picks it',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(value: 'en'));

      tester.semantics
          .performAction(find.semantics.byLabel('Language'), SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(menuEntries(tester), hasLength(4));

      final entry =
          find.semantics.byLabel('繁體中文').evaluate().single.getSemanticsData();
      expect(entry.hasAction(SemanticsAction.tap), isTrue);
      expect(entry.flagsCollection.isEnabled, Tristate.isTrue);
      tester.semantics
          .performAction(find.semantics.byLabel('繁體中文'), SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(chosen, ['zh-Hant']);
      handle.dispose();
    });

    testWidgets('the entry that is selected says so', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(value: 'en'));
      await openByTap(tester);
      Tristate selected(String label) => find.semantics
          .byLabel(label)
          .evaluate()
          .single
          .getSemanticsData()
          .flagsCollection
          .isSelected;
      expect(selected('English'), Tristate.isTrue);
      expect(selected('简体中文'), Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('without a callback it is disabled and offers no action',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(value: 'en', enabled: false));
      final data =
          find.semantics.byLabel('Language').evaluate().single.getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });
}
