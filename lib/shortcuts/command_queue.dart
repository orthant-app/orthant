/// Runs asynchronous work strictly one item at a time, in arrival order.
///
/// Every window command shares one native capture slot: `captureFrontmost`
/// stores a single `AXUIElement`, and `applyFrame` moves whatever is in it. A
/// command is several channel round trips long — capture, screen frames, apply —
/// so two commands in flight together can interleave, and the second one's
/// capture replaces the handle before the first one applies. The first command
/// then moves the *wrong* window, to a rect it computed from a different
/// window's geometry on possibly a different display.
///
/// Nothing else imposes an order: hotkey presses arrive from native as
/// fire-and-forget callbacks with no return value to await, so a burst of them
/// starts a burst of overlapping commands. Serialising here is enough because
/// there is exactly one queue and every user of the capture slot goes through
/// it — the direct region shortcuts, the overlay summon, and the tray item.
///
/// Deliberately no coalescing or dropping. Each task captures afresh when it
/// runs, so a queued command acts on whatever is frontmost at that moment,
/// which keeps a burst predictable rather than merely fast.
class CommandQueue {
  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  /// Told `true` when the queue takes a task while idle, and `false` once the
  /// last task queued has finished, a failure included: once per burst, not
  /// once per task. The platform defers its own work that would hold the
  /// thread the commands share until then (see
  /// `WindowController.setCommandsRunning`).
  void Function(bool busy)? onBusy;

  /// Queue [task] and return a future for *its* completion, errors included.
  Future<void> add(Future<void> Function() task) {
    if (_pending++ == 0) onBusy?.call(true);
    final result = _tail.then((_) => task());
    // The chain itself must survive a failure. If the tail were left rejected,
    // every later command would inherit that error and never run — one thrown
    // exception would kill the shortcuts for the rest of the session, which is
    // a far worse outcome than the race this exists to prevent. The caller's
    // future still carries the error. The count drops here too, before the
    // next task starts, so a burst ends only with its last task.
    _tail = result.then((_) {}, onError: (_) {}).whenComplete(() {
      if (--_pending == 0) onBusy?.call(false);
    });
    return result;
  }
}
