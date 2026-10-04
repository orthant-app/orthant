import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/window_controller_factory.dart';
import 'package:orthant/core/window_controller_macos.dart';
import 'package:orthant/core/window_controller_windows.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('macOS gets the channel-backed controller', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(createWindowController(), isA<MacosWindowController>());
  });

  test('Windows gets its own controller', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(createWindowController(), isA<WindowsWindowController>());
  });

  test('anything else is refused, loudly', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(createWindowController, throwsUnsupportedError);
  });
}
