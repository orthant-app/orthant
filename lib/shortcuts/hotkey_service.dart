import 'package:flutter/services.dart';
import '../core/channel.dart';
import 'bindings.dart';
import 'command_ref.dart';
import 'shortcut_command.dart';

/// What a caller needs of the global-hotkey registrar, with no channel in it.
///
/// Exists so the app's coordinator can be tested without a platform: everything
/// [HotkeyService] does *outbound* is these two calls, and the inbound direction
/// is already plain callbacks.
abstract class HotkeyRegistrar {
  /// Register every bound combo, returning the commands the OS refused.
  Future<Set<CommandRef>> apply(List<Binding> bindings);

  /// Drop every registered global hotkey.
  Future<void> unregisterAll();
}

/// Registers global hotkeys natively (id = [ShortcutCommand] index) and
/// dispatches native `onHotkey(id)` callbacks — to [onSummon] for the grid,
/// to [onCommand] for a placement.
///
/// Dismissal is deliberately not a binding: Esc is grabbed natively, because
/// only the native side knows when the panel is actually on screen, and a
/// bare-Esc grab that outlived the panel would take Esc away from every other
/// app. Those native grabs use reserved ids at 900+, well clear of these.
class HotkeyService implements HotkeyRegistrar {
  HotkeyService({
    required this.onCommand,
    this.onSummon,
    this.onPlacementFailed,
    this.onConfigWindowClosed,
    this.onSaveRegion,
  });

  /// ⌘S on the grid: a block the user wants to keep. Native has already placed
  /// the window; what arrives here is the shape, needing a name and a combo.
  ///
  /// Here for the same reason as [onPlacementFailed]: a MethodChannel has room
  /// for exactly one handler, and this class owns it for the shared channel.
  final void Function(Map<Object?, Object?>)? onSaveRegion;
  final void Function(CommandRef) onCommand;

  /// Overlay summon. Absent (null) means the trigger isn't wired up.
  final void Function()? onSummon;

  /// A grid commit that did not place the window. Lives here only because this
  /// class owns the handler for the shared channel; it is not a hotkey concern.
  /// The grid path is native end to end, so this is its only route back to the
  /// permission recovery the direct shortcuts get for free.
  final void Function()? onPlacementFailed;

  /// The settings/onboarding window was dismissed by its own close button —
  /// a path Dart never initiates and so would otherwise never hear about.
  /// Here for the same reason as [onPlacementFailed]: a MethodChannel has room
  /// for exactly one handler, and this class owns it for the shared channel.
  final void Function()? onConfigWindowClosed;

  static const MethodChannel _channel = MethodChannel(kOrthantChannel);

  /// Register every bound combo, and return the commands the OS **refused**.
  ///
  /// A refusal means macOS or another app already owns that chord. Carbon says
  /// so exactly once, at registration, and never again: a rejected hotkey looks
  /// identical to a live one from here, it is simply never delivered.
  ///
  /// **One call, carrying the whole set.** This used to be `unregisterAll`
  /// followed by a separately awaited `registerHotkey` per binding — twelve
  /// round trips with eleven suspension points in the middle, during which
  /// another caller could start its own replacement. Several can: a rebind, the
  /// end of a recording, a reset, and a native window close all land here, and
  /// two of them overlapping let the *newer* one unregister everything while
  /// the older one was still looping, after which the older loop re-registered
  /// a combo the UI had already moved on from — a live shortcut that the
  /// settings list calls "Not set". The whole swap now happens inside a single
  /// native handler invocation on the main thread, so it cannot interleave, and
  /// the channel delivers calls in order, so the last one to be sent wins.
  ///
  /// Anything other than a list of refused ids counts as *everything* refused —
  /// treating an unexpected reply as success would recreate the silence this
  /// exists to break.
  @override
  Future<Set<CommandRef>> apply(List<Binding> bindings) async {
    _channel.setMethodCallHandler(_handle);

    final applied = <int, CommandRef>{};
    final payload = <Map<String, Object?>>[];
    for (var id = 0; id < bindings.length && id <= _maxId; id++) {
      final b = bindings[id];
      if (!b.isBound) continue;
      applied[id] = b.command;
      payload.add({'id': id, 'keyCode': b.keyCode, 'modifiers': b.modifiers});
    }
    _applied = applied;

    // Object?, not List<Object?>: a typed invokeMethod *throws* on a reply of
    // the wrong shape, and this runs on the launch path. A native side that
    // answered with something unexpected would take the app down rather than
    // report eleven dead shortcuts.
    final reply = await _channel
        .invokeMethod<Object?>('replaceHotkeys', {'bindings': payload});
    if (reply is! List) return applied.values.toSet();
    final refusedIds = reply.whereType<int>().toSet();
    return {
      for (final entry in applied.entries)
        if (refusedIds.contains(entry.key)) entry.value
    };
  }

  /// The last set handed to [apply], keyed by the id it was registered under.
  ///
  /// **The id is the index.** `_completed` puts the eleven built-ins first in
  /// enum order, so they land at 0–10 exactly as they always have, and the
  /// user's regions follow at 11+. Ids need only be unique within one
  /// registration, because [apply] replaces the whole set in a single native
  /// call — which is also what makes this map safe to overwrite outright.
  var _applied = <int, CommandRef>{};

  /// The highest id we may hand the native side.
  ///
  /// `HotkeyManager` reserves 900+ for the overlay's Esc/Return grabs. A
  /// collision would not merely mis-dispatch: it would let a placement shortcut
  /// fire the overlay's dismissal, or be swallowed as one.
  static const int _maxId = 899;

  /// Drop every registered global hotkey (e.g. permission was revoked, or a
  /// combo is being recorded).
  @override
  Future<void> unregisterAll() =>
      _channel.invokeMethod<void>('unregisterAllHotkeys');

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'onHotkey') {
      await debugHandle(call.arguments as int);
    } else if (call.method == 'onPlacementFailed') {
      onPlacementFailed?.call();
    } else if (call.method == 'onConfigWindowClosed') {
      onConfigWindowClosed?.call();
    } else if (call.method == 'onSaveRegion') {
      final a = call.arguments;
      if (a is Map) onSaveRegion?.call(a);
    }
    return null;
  }

  /// Visible for tests: dispatch as if a native press with [id] arrived.
  ///
  /// An id we did not register falls through harmlessly. That covers the
  /// overlay's reserved 900+ grabs, which never reach Dart, and anything stale
  /// — and it is stricter than the old bounds check, which would happily map a
  /// stray id onto whichever command sat at that enum index.
  Future<void> debugHandle(int id) async {
    final ref = _applied[id];
    if (ref == null) return;
    if (ref == const BuiltIn(ShortcutCommand.showGrid)) {
      onSummon?.call();
      return;
    }
    onCommand(ref);
  }
}
