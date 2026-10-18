import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/channel.dart';
import 'package:orthant/permission/ready_screen.dart';
import 'package:orthant/settings/platform_theme.dart';
import 'package:orthant/settings/settings.dart';
import 'package:orthant/settings/settings_window.dart';
import 'package:orthant/shortcuts/bindings.dart';

/// Native shows the config window hidden and reveals it on the screen's first
/// frame, or on a deadline when none is reported. Every screen the window
/// shows reports it, once: the ready screen too, since it is the first window
/// a Windows user ever sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kOrthantChannel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Widget app(Widget screen) => MaterialApp(
        theme: orthantTheme(Brightness.light),
        home: SizedBox(width: 560, height: 600, child: screen),
      );
  Widget ready() => ReadyScreen(
        bindings: runningDefaults(),
        onDone: () {},
        onOpenShortcuts: () {},
      );
  Widget settings() => SettingsWindow(
        settings: const Settings(),
        bindings: runningDefaults(),
        onSettingsChanged: (_) {},
        onRebound: (_) {},
      );

  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  testWidgets('on macOS the ready screen leaves its reveal to the fallback, '
      'and the settings window still reports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ready()));
    await tester.pump();
    expect(calls, isEmpty);
    await tester.pumpWidget(app(settings()));
    await tester.pump();
    expect(calls, ['configFirstFrame']);
  }, variant: macOS);

  testWidgets('the ready screen reports its first frame, once', (tester) async {
    await tester.pumpWidget(app(ready()));
    await tester.pump();
    expect(calls, ['configFirstFrame']);
    await tester.pumpWidget(app(ready()));
    await tester.pump();
    expect(calls, ['configFirstFrame'], reason: 'a rebuild is not a new screen');
  });

  testWidgets('the settings window reports its first frame, once',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(settings()));
    await tester.pump();
    expect(calls, ['configFirstFrame']);
    await tester.pumpWidget(app(settings()));
    await tester.pump();
    expect(calls, ['configFirstFrame']);
  });

  testWidgets('a screen that replaces another reports its own', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ready()));
    await tester.pump();
    await tester.pumpWidget(app(settings()));
    await tester.pump();
    expect(calls, ['configFirstFrame', 'configFirstFrame']);
  });
}
