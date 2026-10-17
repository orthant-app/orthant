import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kReleaseMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/channel.dart';

/// Tells native that a screen of the config window has drawn its first frame.
///
/// Native shows the window hidden (transparent on macOS, cloaked on Windows)
/// and reveals it on this, so a screen appears already painted rather than as
/// an empty window filling in. Every screen the window shows wraps itself in
/// one: a screen that did not would be revealed only by native's deadline,
/// which is what the ready and onboarding screens were until they did. That
/// deadline also means failing to send this costs the effect, not the window.
///
/// Once per screen: a rebuild of the same screen is not a new one.
class FirstFrameReport extends StatefulWidget {
  const FirstFrameReport({
    super.key,
    required this.name,
    this.onMacOS = true,
    required this.child,
  });

  /// For the timing line in Debug and Profile: which screen drew.
  final String name;

  /// False for a screen macOS reveals by its fallback instead. macOS reveals
  /// on this report, which follows the frame's build rather than its
  /// presentation, and a screen that is a cold engine's first frame (the
  /// ready and onboarding screens, at launch) was not shown to be painted by
  /// then. Windows waits for the presented frame, so reports everywhere.
  final bool onMacOS;
  final Widget child;

  @override
  State<FirstFrameReport> createState() => _FirstFrameReportState();
}

class _FirstFrameReportState extends State<FirstFrameReport> {
  @override
  void initState() {
    super.initState();
    if (!widget.onMacOS && defaultTargetPlatform == TargetPlatform.macOS) {
      return;
    }
    final built = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Not kDebugMode: profile builds are the ones worth timing, and that
      // constant is false in exactly those.
      if (!kReleaseMode) {
        debugPrint('[orthant] ${widget.name} first frame: '
            '${DateTime.now().difference(built).inMilliseconds} ms after the '
            'pane was created');
      }
      const MethodChannel(kOrthantChannel)
          .invokeMethod<void>('configFirstFrame');
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
