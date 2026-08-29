import 'package:flutter/material.dart';
import '../settings/mac_theme.dart';
import '../settings/region_glyph.dart';
import '../shortcuts/region_commands.dart';
import 'permission_controller.dart';

/// First-run explainer: why Orthant needs Accessibility, and one button to go
/// grant it. Styled to read as a macOS setup sheet rather than a Material page.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({
    super.key,
    required this.controller,
    this.onOpenAccessibility,
  });
  final PermissionController controller;

  /// What the button does. Null falls back to a plain deep-link; main.dart
  /// supplies one that asks macOS for permission on the first press, which is
  /// where that request now lives — it used to fire at launch, unprompted.
  final VoidCallback? onOpenAccessibility;

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    return Scaffold(
      backgroundColor: t.windowBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A quiet nod to what the app does, built from the real geometry.
              Row(
                children: [
                  for (final cmd in const [
                    RegionCommand.leftHalf,
                    RegionCommand.topRight,
                    RegionCommand.bottomRight,
                    RegionCommand.maximize,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: RegionGlyph(command: cmd),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Orthant needs Accessibility permission',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  color: t.labelPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                // Not "this window will close": since the "try it" step
                // landed, granting advances to it rather than dismissing.
                // Promising a close and then showing another screen reads as
                // the app ignoring you at the one moment it must not.
                'Orthant moves your windows using macOS Accessibility. Enable '
                '“Orthant” under Privacy & Security ▸ Accessibility and '
                'Orthant will pick it up straight away.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.45, color: t.labelSecondary),
              ),
              const SizedBox(height: 22),
              FilledButton(
                // Whatever the host wired, falling back to a bare deep-link.
                // main.dart passes a handler that requests once — putting the
                // system alert behind this click rather than at launch — and
                // opens the pane every time after.
                onPressed: onOpenAccessibility ?? controller.openSettings,
                style: FilledButton.styleFrom(
                  backgroundColor: t.accent,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                  textStyle:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                child: const Text('Open Accessibility Settings'),
              ),
              const SizedBox(height: 16),
              AnimatedBuilder(
                animation: controller,
                builder: (_, _) => Row(
                  children: [
                    Icon(
                      controller.granted
                          ? Icons.check_circle
                          : Icons.more_horiz,
                      size: 15,
                      color: controller.granted
                          ? const Color(0xFF34C759)
                          : t.labelTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      controller.granted
                          ? 'Permission granted'
                          : 'Waiting for permission…',
                      style: TextStyle(
                        fontSize: 12,
                        color: controller.granted
                            ? const Color(0xFF34C759)
                            : t.labelTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
