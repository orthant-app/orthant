import 'dart:io' show Platform;
import 'window_controller.dart';
import 'window_controller_macos.dart';

/// Returns the platform-appropriate controller. macOS only in the MVP;
/// the seam is kept Windows-shaped for later.
WindowController createWindowController() {
  if (Platform.isMacOS) return const MacosWindowController();
  throw UnsupportedError('Orthant supports macOS only in the MVP.');
}
