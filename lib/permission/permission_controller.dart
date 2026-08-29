import 'package:flutter/foundation.dart';
import '../core/window_controller.dart';

enum PermissionStatus { unknown, granted, denied }

/// Tracks Accessibility permission and lets the UI re-check + deep-link to Settings.
class PermissionController extends ChangeNotifier {
  PermissionController(this._wc);
  final WindowController _wc;

  PermissionStatus _status = PermissionStatus.unknown;
  PermissionStatus get status => _status;
  bool get granted => _status == PermissionStatus.granted;

  Future<void> refresh() async {
    final ok = await _wc.checkPermission();
    final next = ok ? PermissionStatus.granted : PermissionStatus.denied;
    if (next != _status) {
      _status = next;
      notifyListeners();
    }
  }

  /// Register Orthant in the Accessibility list.
  ///
  /// `AXIsProcessTrustedWithOptions` with the prompt option is what *creates*
  /// the row the user has to switch on — without it there may be nothing to
  /// switch. Called once on an untrusted launch, and macOS shows its dialog at
  /// most once per app, so it is not a recurring interruption.
  Future<void> register() => _wc.requestPermission();

  /// Take the user to the Accessibility pane. **Only** that.
  ///
  /// This used to request first and then deep-link, which put two surfaces on
  /// screen for a single click: macOS's "…would like to control this computer"
  /// dialog *and* the pane behind it. The dialog carries its own "Open System
  /// Settings" button, so ours was asking the user to answer the same question
  /// twice. Registration now happens once at launch, where it belongs, leaving
  /// this button to do exactly what it says.
  Future<void> openSettings() => _wc.openAccessibilitySettings();
}
