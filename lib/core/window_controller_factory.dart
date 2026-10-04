import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'window_controller.dart';
import 'window_controller_macos.dart';
import 'window_controller_windows.dart';

/// Returns the platform-appropriate controller.
///
/// Keyed on [defaultTargetPlatform] rather than `dart:io`'s `Platform` so a
/// test can choose the branch with `debugDefaultTargetPlatformOverride`; at
/// runtime the two agree. Windows goes through [WindowsWindowController.start]
/// because that factory is where W6 initialises the updater before anything
/// else runs (spec §5.6): the one way to obtain the controller is the one
/// place that cannot be skipped.
WindowController createWindowController() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
      return const MacosWindowController();
    case TargetPlatform.windows:
      return WindowsWindowController.start();
    default:
      throw UnsupportedError('Orthant supports macOS and Windows.');
  }
}
