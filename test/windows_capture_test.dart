import 'package:flutter_test/flutter_test.dart';
import 'package:orthant/core/windows_capture.dart';
import 'package:orthant/core/windows_window_ops.dart';

import 'support/fake_win32.dart';

const own = 1;

FakeDesktop desktop(List<WindowFacts> zOrder, {required int foreground}) =>
    FakeDesktop(ownPid: own)
      ..windows.addAll(zOrder)
      ..foreground = foreground;

void main() {
  test('a placeable foreground window is captured as is, without reactivation',
      () {
    final d = desktop([windowFacts(10)], foreground: 10);
    final c = decideCapture(d);
    expect(c.branch, CaptureBranch.foreground);
    expect(c.window!.hwnd, 10);
    expect(c.reactivate, isFalse);
  });

  test('a borderless foreground window is still captured: the user chose it',
      () {
    final c = decideCapture(desktop([windowFacts(10, framed: false)], foreground: 10));
    expect(c.window!.hwnd, 10);
  });

  test('the desktop is never captured, and nothing beneath it is tried', () {
    // macOS captured an empty Desktop as a window once (M5); the grid then
    // appeared over nothing.
    final d = desktop([windowFacts(5, className: 'WorkerW'), windowFacts(10)],
        foreground: 5);
    final c = decideCapture(d);
    expect(c.window, isNull);
    expect(c.branch, CaptureBranch.none);
    expect(decideCapture(desktop(
            [windowFacts(5, className: 'Progman'), windowFacts(10)],
            foreground: 5))
        .window, isNull);
  });

  test('a minimized foreground window is not captured', () {
    expect(decideCapture(desktop([windowFacts(10, iconic: true)], foreground: 10))
        .window, isNull);
  });

  test('a cloaked or invisible foreground window is not captured', () {
    expect(decideCapture(desktop([windowFacts(10, cloaked: true)], foreground: 10))
        .window, isNull);
    expect(decideCapture(desktop([windowFacts(10, visible: false)], foreground: 10))
        .window, isNull);
  });

  test('a shell surface in front (Start, Alt+Tab, a menu) is not captured', () {
    for (final cls in kShellSurfaceClasses) {
      expect(
          decideCapture(desktop([windowFacts(10, className: cls)], foreground: 10))
              .window,
          isNull,
          reason: cls);
    }
  });

  test('a foreground window DWM will not describe is not captured', () {
    // An unreadable frame is not a frame at the origin: a zero rect would
    // compare equal to a real window there.
    expect(decideCapture(desktop([windowFacts(10, frame: null)], foreground: 10))
        .window, isNull);
    expect(
        decideCapture(desktop([windowFacts(10, frame: const PxRect(5, 5, 5, 400))],
                foreground: 10))
            .window,
        isNull);
  });

  test('with Orthant\'s hidden window in front (the tray path), the topmost '
      'placeable window beneath is captured and reactivated', () {
    final d = desktop([
      windowFacts(2, pid: own, visible: false),
      windowFacts(10),
      windowFacts(11),
    ], foreground: 2);
    final c = decideCapture(d);
    expect(c.branch, CaptureBranch.beneath);
    expect(c.window!.hwnd, 10);
    expect(c.reactivate, isTrue);
    expect(c.reason, 'orthant-hidden-window');
  });

  test('with the taskbar or the tray overflow in front, the same', () {
    for (final cls in kTrayClasses) {
      final d = desktop([windowFacts(3, className: cls), windowFacts(10)],
          foreground: 3);
      final c = decideCapture(d);
      expect(c.window!.hwnd, 10, reason: cls);
      expect(c.reactivate, isTrue, reason: cls);
    }
  });

  test('with no foreground window at all, the same', () {
    final c = decideCapture(desktop([windowFacts(10)], foreground: 0));
    expect(c.window!.hwnd, 10);
    expect(c.reactivate, isTrue);
  });

  test('with Orthant\'s visible settings window in front, the window beneath '
      'is captured but focus stays with the settings window', () {
    final d = desktop([windowFacts(2, pid: own), windowFacts(10)], foreground: 2);
    final c = decideCapture(d);
    expect(c.window!.hwnd, 10);
    expect(c.reactivate, isFalse);
  });

  test('a minimized Orthant window in front counts as hidden: the window '
      'beneath is captured and reactivated', () {
    final d = desktop([windowFacts(2, pid: own, iconic: true), windowFacts(10)],
        foreground: 2);
    final c = decideCapture(d);
    expect(c.window!.hwnd, 10);
    expect(c.reactivate, isTrue);
  });

  test('the walk passes over everything that is not an app window', () {
    final d = desktop([
      windowFacts(2, pid: own, visible: false),
      windowFacts(20, className: 'Shell_TrayWnd'),
      windowFacts(21, toolWindow: true),
      windowFacts(22, framed: false),
      windowFacts(23, pid: own),
      windowFacts(24, cloaked: true),
      windowFacts(25, iconic: true),
      windowFacts(26, frame: null),
      windowFacts(27, className: 'Windows.UI.Core.CoreWindow'),
      windowFacts(30),
    ], foreground: 2);
    expect(decideCapture(d).window!.hwnd, 30);
  });

  test('beneath the tray, an always-on-top window (a pinned video, a sticky '
      'note) is passed over for the window the user was working in, and taken '
      'only when nothing else is placeable', () {
    final d = desktop([
      windowFacts(2, pid: own, visible: false),
      windowFacts(15, topmost: true),
      windowFacts(10),
    ], foreground: 2);
    expect(decideCapture(d).window!.hwnd, 10);

    final onlyPinned = desktop([
      windowFacts(2, pid: own, visible: false),
      windowFacts(15, topmost: true),
      windowFacts(5, className: 'Progman'),
    ], foreground: 2);
    expect(decideCapture(onlyPinned).window!.hwnd, 15);

    final twoPinned = desktop([
      windowFacts(2, pid: own, visible: false),
      windowFacts(15, topmost: true),
      windowFacts(16, topmost: true),
    ], foreground: 2);
    expect(decideCapture(twoPinned).window!.hwnd, 15,
        reason: 'of two always-on-top windows, the higher one');
  });

  test('an always-on-top window in the foreground is captured as is: the user '
      'is working in it', () {
    final c = decideCapture(desktop([windowFacts(15, topmost: true)], foreground: 15));
    expect(c.branch, CaptureBranch.foreground);
    expect(c.window!.hwnd, 15);
  });

  test('nothing placeable beneath gives none, not a guess', () {
    final d = desktop([
      windowFacts(2, pid: own, visible: false),
      windowFacts(20, className: 'Shell_TrayWnd'),
      windowFacts(5, className: 'Progman'),
    ], foreground: 2);
    final c = decideCapture(d);
    expect(c.window, isNull);
    expect(c.branch, CaptureBranch.none);
  });

  test('the walk stops at the first placeable window', () {
    final d = desktop([
      windowFacts(2, pid: own, visible: false),
      windowFacts(10),
      for (var i = 0; i < 50; i++) windowFacts(100 + i),
    ], foreground: 2);
    decideCapture(d);
    expect(d.pulled, 2, reason: 'zOrder is lazy, and the decision reads no further');
  });

  test('the class-name sets hold the names Windows uses, spelled out', () {
    // The tests above loop over the constants, so a deleted or misspelled
    // entry would leave them green; these literals would not.
    expect(kDesktopClasses, containsAll(['Progman', 'WorkerW']));
    expect(kTrayClasses, containsAll([
      'Shell_TrayWnd',
      'Shell_SecondaryTrayWnd',
      'NotifyIconOverflowWindow',
      'TopLevelWindowForOverflowXamlIsland',
    ]));
    expect(kShellSurfaceClasses, containsAll([
      'Windows.UI.Core.CoreWindow',
      'XamlExplorerHostIslandWindow',
      '#32768',
    ]));
  });
}
