import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Live display labels shared by the settings window and its dialog routes.
/// Keep this above the Navigator so an already-open picker sees layout changes.
class KeyboardLabels extends InheritedWidget {
  const KeyboardLabels({super.key, required this.labels, required super.child});

  final Map<int, String> labels;

  static Map<int, String> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KeyboardLabels>()?.labels ??
      const {};

  @override
  bool updateShouldNotify(KeyboardLabels oldWidget) =>
      !mapEquals(labels, oldWidget.labels);
}
