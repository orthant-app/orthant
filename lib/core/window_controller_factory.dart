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
/// because that factory starts the updater before anything else runs: the
/// one way to obtain the controller is the one place that cannot be skipped.
/// [onUpdaterShutdown] is how Windows' updater asks the app to quit once it
/// has started an update's installer; macOS's updater quits the app itself.
WindowController createWindowController({void Function()? onUpdaterShutdown}) {
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
      return const MacosWindowController();
    case TargetPlatform.windows:
      return WindowsWindowController.start(
          onUpdaterShutdown: onUpdaterShutdown);
    default:
      throw UnsupportedError('Orthant supports macOS and Windows.');
  }
}
