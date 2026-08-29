import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/geometry.dart';
import 'grid_overlay.dart';
import 'grid_selection.dart';

/// Runs the overlay UI on the second Flutter engine. The `overlayMain`
/// entrypoint itself lives in `lib/main.dart` — macOS resolves an entrypoint
/// name only against the library containing `main()`.
void runOverlayApp() => runApp(const OverlayApp());

const MethodChannel _overlay = MethodChannel('app.orthant/overlay');

/// Public only so a test can pump it. This is the one part of the overlay a
/// Dart test can reach — everything else about the panel is native.
class OverlayApp extends StatefulWidget {
  const OverlayApp({super.key});
  @override
  State<OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<OverlayApp> {
  final _grid = GlobalKey<GridOverlayState>();

  /// Keys that arrived before there was a grid to give them to.
  ///
  /// Native grabs `Esc`, `Return` and the arrows *before* it puts the panel on
  /// screen, precisely so nothing falls through to the app behind — which means
  /// the window between a summon and this engine's first frame is a window in
  /// which real keystrokes are delivered here with `_grid.currentState` still
  /// null. Measured summon→first-frame is a median 44 ms and has been seen at
  /// 368 ms on a cold engine, so it is wide enough to type into. Dropped, the
  /// keys are silent: an arrow does nothing and the `Return` behind it commits
  /// nothing.
  final _pending = <void Function(GridOverlayState)>[];

  int? _sessionId;
  WinRect? _frame;
  String _appName = '';
  Uint8List? _appIcon;
  bool _active = false;

  /// Whether to offer the ⌘S hint. Pushed with the grid, so it is already
  /// correct by the time a summon arrives — nothing on the latency path.
  bool _saveHint = false;
  int _cols = 6;
  int _rows = 6;
  double _gap = 0;
  bool _visible = false;
  double? _triggerAtMs;

  @override
  void initState() {
    super.initState();
    _overlay.setMethodCallHandler(_handle);
    // Tell native the handler is live. A summon sent before this point is
    // dropped by the engine, and the panel sits on screen empty; native
    // replays the payload when it sees this.
    _overlay.invokeMethod<void>('ready');
  }

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'summon':
        final a = (call.arguments as Map).cast<String, dynamic>();
        _sessionId = a['sessionId'] as int;
        _triggerAtMs = (a['triggerMs'] as num).toDouble();
        _frame = WinRect((a['x'] as num).toDouble(), (a['y'] as num).toDouble(),
            (a['w'] as num).toDouble(), (a['h'] as num).toDouble());
        _appName = a['appName'] as String? ?? '';
        _appIcon = a['appIcon'] as Uint8List?;
        _active = a['active'] as bool? ?? false;
        // Defaulted rather than required: an older native side, or a summon
        // that raced a settings push, still draws a usable grid.
        _cols = a['cols'] as int? ?? _cols;
        _rows = a['rows'] as int? ?? _rows;
        _gap = (a['gap'] as num?)?.toDouble() ?? _gap;
        _saveHint = a['saveHint'] as bool? ?? false;
        assert(() {
          debugPrint('[orthant] overlay summon: saveHint=$_saveHint');
          return true;
        }());
        // Anything still queued belongs to a session that is over.
        _pending.clear();
        setState(() => _visible = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _drainPending();
          final t0 = _triggerAtMs;
          if (t0 == null) return;
          _overlay.invokeMethod<void>(
              'firstFrame', DateTime.now().millisecondsSinceEpoch - t0);
          _triggerAtMs = null;
        });
      case 'setActive':
        setState(() => _active = call.arguments as bool);
      case 'commitCurrent':
        if (call.arguments == _sessionId) {
          _onGrid((g) => g.commitCurrent());
        }
      // ⌘S — grabbed natively for the same reason Return is: the panel is
      // non-key and never sees a key event of its own.
      case 'saveCurrent':
        if (call.arguments == _sessionId) {
          _onGrid((g) => g.saveCurrent());
        }
      // {sessionId, direction, extend} — an arrow key, grabbed natively because
      // this panel is non-activating and never sees a key event of its own.
      case 'moveSelection':
        final a = call.arguments as Map;
        if (a['sessionId'] != _sessionId) return null;
        final d = GridDirection.values.asNameMap()[a['direction'] as String];
        if (d == null) return null;
        _onGrid((g) => g.moveSelection(d, extend: a['extend'] == true));
      case 'hidden':
        // Drop the tree and let the controller go: zero tickers while hidden.
        _pending.clear();
        setState(() {
          _visible = false;
          _sessionId = null;
        });
    }
    return null;
  }

  /// Act on the grid, or hold the action until there is one. See [_pending].
  void _onGrid(void Function(GridOverlayState) action) {
    final grid = _grid.currentState;
    if (grid == null) {
      _pending.add(action);
      return;
    }
    action(grid);
  }

  /// Replay what arrived early, in the order it arrived — an arrow and then the
  /// `Return` behind it only mean anything in that order.
  void _drainPending() {
    final grid = _grid.currentState;
    if (grid == null || _pending.isEmpty) return;
    final queued = List.of(_pending);
    _pending.clear();
    for (final action in queued) {
      action(grid);
    }
  }

  void _send(String method, [Object? args]) {
    final id = _sessionId;
    if (id == null) return;
    _overlay.invokeMethod<void>(
        method, args is Map ? {'sessionId': id, ...args} : {'sessionId': id});
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final sessionId = _sessionId;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: (!_visible || frame == null || sessionId == null)
            ? const SizedBox.shrink()
            : MouseRegion(
                onEnter: (_) => _send('becameActive'),
                child: GridOverlay(
                  key: _grid,
                  sessionId: sessionId,
                  displayFrame: frame,
                  appName: _appName,
                  appIcon: _appIcon,
                  active: _active,
                  cols: _cols,
                  rows: _rows,
                  gap: _gap,
                  onBeginDrag: () => _send('beginDrag'),
                  onEndDrag: () => _send('endDrag'),
                  onCancel: () => _send('hide'),
                  saveHint: _saveHint,
                  onSave: (b, r) => _send('saveRegion', {
                    'cols': _cols,
                    'rows': _rows,
                    'c0': b.c0,
                    'c1': b.c1,
                    'r0': b.r0,
                    'r1': b.r1,
                    'x': r.x,
                    'y': r.y,
                    'w': r.width,
                    'h': r.height,
                  }),
                  onCommit: (r) => _send('commit', {
                    'x': r.x,
                    'y': r.y,
                    'w': r.width,
                    'h': r.height,
                  }),
                ),
              ),
      ),
    );
  }
}
