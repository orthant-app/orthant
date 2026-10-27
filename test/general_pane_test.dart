import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller.dart';
import 'package:orthant/settings/general_pane.dart';
import 'package:orthant/settings/grid_preview.dart';
import 'package:orthant/settings/mac_popup_button.dart';
import 'package:orthant/settings/mac_stepper.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/settings.dart';

import 'support/carbon_terms.dart';
import 'support/locales.dart';
import 'support/localized_host.dart';
import 'support/no_english.dart';

void main() {
  late List<Settings> changes;

  Widget host(Settings settings) {
    changes = [];
    return MaterialApp(
      theme: orthantTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          width: 560,
          child: GeneralPane(
            settings: settings,
            onSettingsChanged: changes.add,
            permissionGranted: true,
            loginStatus: LoginItemStatus.disabled,
            bindings: macDefaults,
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

  group('what a screen reader hears on the steppers', () {
    Set<String> stepperLabels(WidgetTester tester) => {
          for (final node
              in find.semantics.byPredicate((_) => true).evaluate())
            if (node.label.contains(RegExp(r'[,，]')) &&
                node.label.contains(RegExp(r'[0-9]')))
              node.label,
        };

    testWidgets('English: caption and value, then the direction',
        (tester) async {
      await tester.pumpWidget(host(const Settings(gaps: true)));
      expect(stepperLabels(tester), containsAll({
        'Columns 6, increase',
        'Columns 6, decrease',
        'Rows 6, increase',
        'Rows 6, decrease',
        'Size 8 pt, increase',
        'Size 8 pt, decrease',
      }));
    });

    testWidgets('Chinese: the same, one whole message each', (tester) async {
      for (final (locale, columns, rows, up, down) in [
        (kSimplified, '列数', '行数', '增加', '减少'),
        (kTraditional, '欄數', '列數', '增加', '減少'),
      ]) {
        await tester.pumpWidget(localizedApp(
          locale,
          SizedBox(
            width: 560,
            child: GeneralPane(
              settings: const Settings(gaps: true),
              onSettingsChanged: (_) {},
              permissionGranted: true,
              loginStatus: LoginItemStatus.disabled,
              bindings: macDefaults,
            ),
          ),
        ));
        expect(stepperLabels(tester), containsAll({
          '$columns 6，$up',
          '$columns 6，$down',
          '$rows 6，$up',
          '$rows 6，$down',
          '大小 8 pt，$up',
          '大小 8 pt，$down',
        }));
      }
    });
  });
  group('the Language group', () {
    const english = 'The update window changes language the next time Orthant '
        'starts.';

    /// Tall enough that the whole pane is on screen: the group is the last
    /// one, and a row below the fold is findable but not tappable.
    Future<void> tall(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    GeneralPane pane({
      String? choice,
      ValueChanged<String?>? onChanged,
      ScrollController? controller,
    }) =>
        GeneralPane(
          settings: const Settings(),
          onSettingsChanged: (_) {},
          permissionGranted: true,
          loginStatus: LoginItemStatus.disabled,
          bindings: macDefaults,
          languageChoice: choice,
          onLanguageChanged: onChanged,
          scrollController: controller,
        );

    Future<void> pump(WidgetTester tester, GeneralPane pane,
        {Locale? locale}) async {
      await tall(tester);
      final sized = SizedBox(width: 560, child: pane);
      await tester.pumpWidget(locale == null
          ? MaterialApp(
              theme: orthantTheme(Brightness.light),
              home: Scaffold(body: sized),
            )
          : localizedApp(locale, sized));
      await tester.pumpAndSettle();
    }

    final button = find.byType(MacPopUpButton<String?>);

    /// The words of the open menu's entries, top to bottom.
    List<String> entries(WidgetTester tester) {
      final texts = find.descendant(
          of: find.byType(MenuItemButton), matching: find.byType(Text));
      final found = <(double, String)>[
        for (final e in texts.evaluate())
          (
            tester.getTopLeft(find.byElementPredicate((x) => x == e)).dy,
            (e.widget as Text).data!,
          ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      return [for (final (_, name) in found) name];
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('comes last, after Startup, on both platforms',
        (tester) async {
      await pump(tester, pane());
      final language = tester.getTopLeft(find.text('Language')).dy;
      expect(language, greaterThan(tester.getTopLeft(find.text('Startup')).dy));
      expect(language,
          greaterThan(tester.getTopLeft(find.text('Launch at login')).dy));
      // The picker sits beside its label, in the same row.
      expect(tester.getTopLeft(button).dy, closeTo(language, 8));
    }, variant: TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.windows}));

    for (final (locale, system) in [
      (kEnglish, 'System'),
      (kSimplified, '跟随系统'),
      (kTraditional, '跟隨系統'),
      (kHongKong, '跟隨系統'),
    ]) {
      testWidgets('${locale.toLanguageTag()}: lists System, then each '
          'language in its own script', (tester) async {
        await pump(tester, pane(onChanged: (_) {}), locale: locale);
        await open(tester);
        expect(entries(tester), [system, 'English', '简体中文', '繁體中文']);
      });
    }

    testWidgets('System is what a fresh install shows', (tester) async {
      await pump(tester, pane());
      expect(find.descendant(of: button, matching: find.text('System')),
          findsOneWidget);
      await pump(tester, pane(), locale: kSimplified);
      expect(find.descendant(of: button, matching: find.text('跟随系统')),
          findsOneWidget);
    });

    testWidgets('shows the language that is stored, in its own script',
        (tester) async {
      for (final (choice, shown) in [
        ('en', 'English'),
        ('zh-Hans', '简体中文'),
        ('zh-Hant', '繁體中文'),
        ('zh-TW', '繁體中文'),
        ('zh-Hant-HK', '繁體中文'),
        ('fr', 'System'),
      ]) {
        await pump(tester, pane(choice: choice));
        expect(find.descendant(of: button, matching: find.text(shown)),
            findsOneWidget,
            reason: choice);
      }
    });

    testWidgets('choosing a language reports its tag; System reports null',
        (tester) async {
      final picked = <String?>[];
      await pump(tester, pane(choice: 'en', onChanged: picked.add));
      await open(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, '繁體中文'));
      await tester.pumpAndSettle();
      expect(picked, ['zh-Hant']);

      await open(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, 'System'));
      await tester.pumpAndSettle();
      expect(picked, ['zh-Hant', null]);
    });

    testWidgets('choosing the entry a Hong Kong choice already belongs to '
        'does nothing, so Hong Kong is not flattened', (tester) async {
      final picked = <String?>[];
      await pump(tester, pane(choice: 'zh-Hant-HK', onChanged: picked.add));
      expect(find.descendant(of: button, matching: find.text('繁體中文')),
          findsOneWidget);
      await open(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, '繁體中文'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);

      // And it is still a choice that can be left.
      await open(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, '简体中文'));
      await tester.pumpAndSettle();
      expect(picked, ['zh-Hans']);
    });

    testWidgets('System, picked while System is shown, does nothing',
        (tester) async {
      final picked = <String?>[];
      await pump(tester, pane(onChanged: picked.add));
      await open(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, 'System'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
    });

    testWidgets('says under the picker that the update window follows at the '
        'next start', (tester) async {
      await pump(tester, pane());
      expect(find.text(english), findsOneWidget);
      expect(tester.getTopLeft(find.text(english)).dy,
          greaterThan(tester.getBottomLeft(button).dy - 1));

      for (final (locale, note) in [
        (kSimplified, '更新窗口会在下次启动 Orthant 时切换语言。'),
        (kTraditional, '更新視窗會在下次啟動 Orthant 時切換語言。'),
        (kHongKong, '更新視窗會在下次啟動 Orthant 時切換語言。'),
      ]) {
        await pump(tester, pane(), locale: locale);
        expect(find.text(note), findsOneWidget, reason: locale.toLanguageTag());
      }
    });

    testWidgets('is reached by Tab, opened with Space, moved with the arrows '
        'and chosen with Return', (tester) async {
      final picked = <String?>[];
      await pump(tester, pane(onChanged: picked.add));

      bool onPicker() {
        final context = FocusManager.instance.primaryFocus?.context;
        return context != null &&
            find
                .descendant(
                    of: button,
                    matching: find.byElementPredicate((e) => e == context))
                .evaluate()
                .isNotEmpty;
      }

      var tabs = 0;
      while (!onPicker() && tabs++ < 40) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
      }
      expect(onPicker(), isTrue, reason: 'Tab never reached the picker');

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(entries(tester), hasLength(4));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picked, ['zh-Hans']);
    });

    testWidgets('a screen reader gets a button it can operate',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, pane(choice: 'zh-Hans', onChanged: (_) {}));
      final node = find.semantics
          .byPredicate((n) =>
              n.label == 'Language' &&
              n.getSemanticsData().hasAction(SemanticsAction.tap))
          .evaluate()
          .single
          .getSemanticsData();
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      expect(node.value, '简体中文');
      handle.dispose();
    });

    testWidgets('without a callback it is shown, but inert', (tester) async {
      await pump(tester, pane(choice: 'en'));
      await open(tester);
      expect(find.byType(MenuItemButton), findsNothing);
    });

    for (final (locale, choice) in [
      (kSimplified, null),
      (kSimplified, 'zh-Hans'),
      (kTraditional, 'zh-Hant'),
      (kHongKong, 'zh-Hant-HK'),
    ]) {
      testWidgets('${locale.toLanguageTag()} (choice: $choice): no English is '
          'left, and the open menu holds only English\'s own name',
          (tester) async {
        await pump(tester, pane(choice: choice, onChanged: (_) {}),
            locale: locale);
        expectNoEnglish(tester);
        await open(tester);
        expectNoEnglish(tester, allow: {'English'});
      });
    }

    testWidgets('switching language re-renders General in it and keeps the '
        'scroll position', (tester) async {
      // Short, so the pane scrolls and the last group is only reached by
      // scrolling to it.
      await tester.binding.setSurfaceSize(const Size(600, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ScrollController();
      addTearDown(controller.dispose);

      var locale = kEnglish;
      String? choice;
      await tester.pumpWidget(StatefulBuilder(
        builder: (context, setState) => localizedApp(
          locale,
          SizedBox(
            width: 560,
            child: pane(
              choice: choice,
              controller: controller,
              onChanged: (tag) => setState(() {
                choice = tag;
                locale = kSimplified;
              }),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Startup'), findsOneWidget);

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final before = controller.offset;
      final scrollable = tester.state(find.byType(Scrollable));
      expect(before, greaterThan(100), reason: 'the pane must have scrolled');

      await open(tester);
      await tester.tap(find.widgetWithText(MenuItemButton, '简体中文'));
      await tester.pumpAndSettle();

      expect(find.text('语言'), findsOneWidget);
      expect(find.text('启动'), findsOneWidget);
      expect(find.text('Startup'), findsNothing);
      expect(find.text('Language'), findsNothing);
      expect(find.descendant(of: button, matching: find.text('简体中文')),
          findsOneWidget);
      // The same scrollable, not a rebuilt one, and its offset is where it
      // was or as far as the new content (shorter in Chinese) allows, never 0.
      expect(tester.state(find.byType(Scrollable)), same(scrollable));
      expect(controller.offset,
          closeTo(before.clamp(0, controller.position.maxScrollExtent), 0.01));
      expect(controller.offset, greaterThan(50));
    });
  });
}
