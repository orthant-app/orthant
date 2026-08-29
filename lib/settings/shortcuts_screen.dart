import 'dart:async';

import 'package:flutter/material.dart';
import '../shortcuts/bindings.dart';
import '../shortcuts/command_ref.dart';
import '../shortcuts/custom_region.dart';
import '../shortcuts/region_commands.dart';
import '../shortcuts/shortcut_command.dart';
import 'keycap.dart';
import 'mac_control.dart';
import 'mac_theme.dart';
import 'recording_field.dart';
import 'region_glyph.dart';
import 'region_picker_sheet.dart';

const Map<ShortcutCommand, String> kCommandLabels = {
  ShortcutCommand.showGrid: 'Open grid',
  ShortcutCommand.leftHalf: 'Left half',
  ShortcutCommand.rightHalf: 'Right half',
  ShortcutCommand.topHalf: 'Top half',
  ShortcutCommand.bottomHalf: 'Bottom half',
  ShortcutCommand.topLeft: 'Top-left quarter',
  ShortcutCommand.topRight: 'Top-right quarter',
  ShortcutCommand.bottomLeft: 'Bottom-left quarter',
  ShortcutCommand.bottomRight: 'Bottom-right quarter',
  ShortcutCommand.maximize: 'Maximize',
  ShortcutCommand.center: 'Center',
};

/// The MVP rebind picker, styled as a macOS preferences pane.
///
/// Recording happens **inline** in the row (the AppKit convention — System
/// Settings, Rectangle and Raycast all work this way) rather than in a modal.
class ShortcutsScreen extends StatefulWidget {
  const ShortcutsScreen({
    super.key,
    required this.bindings,
    required this.onRebound,
    this.onRestoreBindings,
    this.unavailable = const {},
    this.onCaptureStart,
    this.onCaptureEnd,
    this.onResetBindings,
    this.permissionGranted = true,
    this.onOpenAccessibility,
    this.scrollController,
    this.regions = const [],
    this.gridCols = 6,
    this.gridRows = 6,
    this.onRegionSaved,
    this.onRegionDeleted,
    this.pendingRegion,
    this.onPendingConsumed,
  });

  /// A shape handed over by ⌘S on the grid, to open the picker on.
  final CustomRegion? pendingRegion;
  final VoidCallback? onPendingConsumed;

  /// The user's own regions, in list order. Their rows follow the eleven
  /// built-ins, which is the order [BindingsStore] already guarantees.
  final List<CustomRegion> regions;

  /// The live overlay grid, used only as the picker's starting denominator.
  final int gridCols;
  final int gridRows;

  /// Add or update a region and its combo, as one transaction. Null hides the
  /// add row entirely — the pane is then read-only for regions.
  final void Function(RegionDraft)? onRegionSaved;

  /// Remove a region and its binding together.
  final void Function(String id)? onRegionDeleted;

  /// Owned by the window, one per pane, so a pane's scroll position survives a
  /// tab switch. Nothing reads a position from it — the window's size is
  /// AppKit's, and this pane simply scrolls inside whatever it is given.
  final ScrollController? scrollController;

  /// Whether any of these can actually fire.
  ///
  /// Said here as well as in General, which is not duplication: this pane is a
  /// list of eleven ordinary-looking shortcuts that, without the grant, all do
  /// nothing — the same silence the [unavailable] warnings exist to break, and
  /// this is the tab someone opens when pressing a key has no effect. Nobody
  /// reads the *other* tab to explain the one they are looking at.
  final bool permissionGranted;
  final VoidCallback? onOpenAccessibility;

  /// Restore every shortcut to its default.
  ///
  /// Until this existed there was no way back from a rebind at all: taking a
  /// combo another command owns *unbinds that one*, so a few careless changes
  /// could leave several commands unset with no undo short of deleting the
  /// preferences by hand.
  final VoidCallback? onResetBindings;

  final List<Binding> bindings;

  /// Commands whose combo the OS refused to register — macOS or another app
  /// already owns the chord. Marked in the row because the binding is otherwise
  /// indistinguishable from a working one: it is stored, it is displayed, and
  /// it never fires.
  final Set<CommandRef> unavailable;

  /// Called with the updated binding when the user records a new combo, and
  /// with an unbound binding when they clear one.
  final void Function(Binding) onRebound;

  /// Make the bindings exactly this — the way back from a change that touched
  /// more than one row.
  ///
  /// Taking an occupied combination unbinds another command, and *Reset
  /// Shortcuts* rewrites all of them. Deleting a single region has had an Undo
  /// since M9; these two, which change more, had none — which is the whole
  /// reason taking an occupied combination used to be refused outright. One
  /// snapshot of [bindings] handed back covers both.
  final void Function(List<Binding>)? onRestoreBindings;

  /// Suspend / resume the global hotkeys around recording — without this the
  /// combo being recorded also *fires*, so a window jumps mid-capture.
  final Future<void> Function()? onCaptureStart;
  final Future<void> Function()? onCaptureEnd;

  @override
  State<ShortcutsScreen> createState() => _ShortcutsScreenState();
}

class _ShortcutsScreenState extends State<ShortcutsScreen> {
  @override
  void initState() {
    super.initState();
    _openPendingIfAny();
  }

  @override
  void didUpdateWidget(covariant ShortcutsScreen old) {
    super.didUpdateWidget(old);
    if (widget.pendingRegion != old.pendingRegion) _openPendingIfAny();
    if (widget.regions != old.regions) {
      final live = {
        for (final c in ShortcutCommand.values) BuiltIn(c).jsonName,
        for (final r in widget.regions) Custom(r.id).jsonName,
      };
      // Only ids that are gone, so a key still in use is never swapped for a
      // fresh one under a row that is about to rebuild.
      _rowKeys.removeWhere((id, _) => !live.contains(id));
    }
    // The row a save asked to reveal usually arrives on an update like this
    // one, a frame or more after the request.
    if (_flash != null && !_flashRevealed) _scheduleReveal();
  }

  /// Open the picker on a shape ⌘S handed over.
  ///
  /// Consumed *before* the sheet is shown, not after it closes: the sheet
  /// awaits a dialog route, and anything that rebuilds this pane in the
  /// meantime would otherwise open a second one behind the first.
  void _openPendingIfAny() {
    final pending = widget.pendingRegion;
    if (pending == null) return;
    widget.onPendingConsumed?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openPicker(pending, isNew: true);
    });
  }

  /// A picker asked for while one was already up.
  ///
  /// ⌘S can hand over a shape at any moment, including while the user is
  /// editing a region — the overlay is summonable with Settings open. Pushing a
  /// second sheet stacked two modals *and* overwrote the single retained route
  /// handle, so closing the window then tore down only the newer one and the
  /// first survived into the next open.
  ///
  /// Queued rather than dropped or substituted: dropping loses a shape the user
  /// explicitly asked to keep, and replacing throws away the edit they were in
  /// the middle of. Each is shown as the one before it closes.
  ///
  /// A **list**, not one slot. ⌘S can be pressed as often as the user likes, and
  /// a single slot silently discarded every handoff but the last — the same
  /// class of loss queueing exists to prevent, one level down.
  final _queuedPickers = <({CustomRegion? initial, bool isNew})>[];

  /// Whether a picker is being presented — from the push until both the route
  /// is gone *and* the hotkeys are back.
  ///
  /// Deliberately **not** [_pickerRouteRef], which the teardown owns and which
  /// must be released the moment the route is gone. Using that as the admission
  /// gate meant a request arriving during a slow hotkey restore found it already
  /// null and opened straight away, overtaking everything queued behind it.
  bool _presenting = false;

  CommandRef? _recording;
  CommandRef? _hovered;
  CommandRef? _focused;
  /// Which row a screen reader's cursor is on. Tracked apart from [_focused]
  /// because the two move independently.
  CommandRef? _readerOn;

  /// The row's title.
  ///
  /// Custom regions resolve through the region list in M9 Task 11; every ref
  /// reaching here today is a [BuiltIn].
  String _labelFor(CommandRef ref) => switch (ref) {
        BuiltIn(:final command) => kCommandLabels[command]!,
        // Falls back rather than throwing: the loader drops a binding whose
        // region did not survive, so a nameless row should be unreachable —
        // and a build-time throw in Release is a featureless grey box, which
        // is how the last one of these presented.
        Custom(:final id) => _regionFor(id)?.name ?? 'Custom region',
      };

  CustomRegion? _regionFor(String id) {
    for (final r in widget.regions) {
      if (r.id == id) return r;
    }
    return null;
  }

  CustomRegion? _customOf(CommandRef ref) =>
      switch (ref) { BuiltIn() => null, Custom(:final id) => _regionFor(id) };

  /// The region a row's glyph should draw, or null for the summon — which opens
  /// the grid rather than placing a window anywhere in particular.
  RegionCommand? _regionOf(CommandRef ref) => switch (ref) {
        BuiltIn(:final command) => command.region,
        Custom() => null,
      };

  /// The stored binding for [c], or an unbound one.
  ///
  /// The `orElse` is load-bearing, and its absence was a **blank pane** in
  /// Release: a bare `firstWhere` throws `StateError` for a command the list
  /// has no entry for, and a build-time throw in a release build renders as an
  /// `ErrorWidget` with no text — a featureless grey box. The list is empty
  /// whenever preferences have not been loaded, and the panes doing this same
  /// lookup with an `orElse` (General, Ready) merely showed "Not set", which is
  /// why only this one looked broken rather than empty.
  ///
  /// A missing command is a row with no shortcut. It is never a reason to take
  /// the pane down.
  Binding _bindingFor(CommandRef c) => widget.bindings.firstWhere(
    (b) => b.command == c,
    orElse: () => Binding.unbound(c),
  );

  Future<void> _startRecording(CommandRef cmd) async {
    // Recording starts **first**, before the suspend.
    //
    // Suspending the global hotkeys is a method-channel call, and gating the UI
    // on it meant that if it threw or was slow the click did nothing at all —
    // no pill, no error, a row that simply refused to be clicked. Nothing on
    // screen could say why, because nothing on screen had changed.
    //
    // The original order existed so the combo being recorded cannot also fire.
    // That is still true a moment later, and the risk it trades against is
    // tiny: firing once, only if a key is pressed inside the round trip. A row
    // that cannot be clicked is not a smaller bug than a window that jumps.
    if (!mounted) return;
    // A pending question does not follow the recording to another row. Its
    // footer button acts on the row it was raised for — clicking "Use it here"
    // after moving on would rebind a row the user had stopped looking at.
    final stale = _pending != null && _pending!.row != cmd;
    if (stale) _noticeTimer?.cancel();
    setState(() {
      if (stale) {
        _notice = null;
        _pending = null;
      }
      _recording = cmd;
    });
    await widget.onCaptureStart?.call();
  }

  Future<void> _stopRecording() async {
    // Idempotent, so it is safe to call from anywhere that is about to do
    // something a live recording must not be underneath. Without the guard a
    // defensive call on a path where nothing was recording hands back a hotkey
    // suspension this pane never took — six lifecycle tests caught exactly that.
    if (_recording == null) return;
    if (mounted) {
      // A pending question goes down with the recording that raised it. Its
      // notice is sticky — it has no timer of its own — so nothing else ever
      // would, and esc would leave the footer asking about a row that had
      // stopped listening.
      final hadQuestion = _pending != null;
      if (hadQuestion) _noticeTimer?.cancel();
      setState(() {
        if (hadQuestion) _notice = null;
        _recording = null;
        _pending = null;
      });
    }
    await widget.onCaptureEnd?.call();
  }

  NavigatorState? _navigator;

  /// The picker's route while it is on the navigator, so [dispose] can remove
  /// exactly that one.
  DialogRoute<void>? _pickerRouteRef;

  /// Named for the debugger and for observers; the route object above is what
  /// the take-down actually uses.
  static const _pickerRoute = 'region-picker';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigator = Navigator.of(context, rootNavigator: true);
  }

  /// Take the picker route down with the pane.
  ///
  /// A route lives on the root navigator — above `home`, outside this subtree —
  /// so closing the settings window would otherwise leave the sheet pushed, and
  /// the next open showed a modal over a window the user had only just asked
  /// for. Removing it also completes the route's future, so `endCapture` runs
  /// and the global hotkeys come back.
  void _disposePicker() {
    final navigator = _navigator;
    final route = _pickerRouteRef;
    if (route == null || navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // A microtask later, and the hop is load-bearing: Flutter takes a route
      // out of `_history` and *then* defers `Route.dispose` to a microtask
      // (navigator.dart:3473), so in between `route.navigator` is still
      // non-null for a route that is already gone — and `finalizeRoute` asserts
      // on exactly that. A post-frame callback runs before that microtask.
      scheduleMicrotask(() {
        if (!navigator.mounted || route.navigator == null) return;
        if (route.isActive) {
          navigator.removeRoute(route);
        } else {
          navigator.finalizeRoute(route);
        }
      });
    });
  }

  /// The transient message shown in the footer, in place of the hint.
  ///
  /// **Not a `SnackBar`.** One covered the *Reset Shortcuts* button — a bar that
  /// obscures a control is worse than no bar — and the queue behind it lives on
  /// the app-level messenger, above `home`, which cost four review rounds of
  /// lifetime bugs on its own: an entrance animation that froze with the window,
  /// a timer that was never armed, a replacement stranded behind its
  /// predecessor, a notice that outlived the window and greeted the next open.
  ///
  /// The footer already swaps its text while recording, so this is a third
  /// state of a line that was going to be there anyway. It cannot cover
  /// anything, it cannot outlive the pane, and it needs no queue.
  ({String message, String? actionLabel, VoidCallback? action})? _notice;
  Timer? _noticeTimer;

  /// A combination the user pressed that something else already owns.
  ///
  /// Kept while the row goes on **listening**, so that pressing it again — or
  /// clicking the footer's button — takes it. Refusing outright and dropping
  /// out of recording made getting a taken combination onto a row a six-step
  /// errand through a command ten rows away.
  ({CommandRef row, int keyCode, int modifiers, CommandRef owner})? _pending;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    // A recording suspends every global hotkey, and this pane can go away
    // *while* one is live: `SettingsWindow` switches panes with a `switch` on
    // the tab, so clicking General disposes this outright. Nothing else would
    // then hand the suspension back, and the only backstop is the window's own
    // close — so every shortcut stayed dead for as long as the user left the
    // window open on the other tab, with nothing on screen to say so.
    //
    // The fourth path in this family after M5 (window close), M10 (the picker's
    // exits) and the picker-over-recording fix below. *Recording suspends, and
    // the thing that resumes must be reached by every way out.*
    //
    // Unawaited by necessity — dispose cannot wait — and its error swallowed,
    // because a rejected channel call from a disposed widget would otherwise
    // surface as an uncaught async error with nothing left to handle it.
    if (_recording != null) {
      widget.onCaptureEnd?.call().catchError((Object _) {});
    }
    _disposePicker();
    super.dispose();
  }

  /// Put a line in the footer, optionally with one control beside it.
  ///
  /// [sticky] withholds the dismissal timer, for a notice that asks a question
  /// rather than reporting something done: a question that vanishes while it is
  /// being read is worse than none. A sticky notice is taken down by
  /// [_stopRecording], which owns the state that raised it.
  void _notify(
    String message, {
    Duration? visible,
    String? actionLabel,
    VoidCallback? action,
    bool sticky = false,
  }) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(
      () => _notice = (
        message: message,
        actionLabel: actionLabel,
        action: action,
      ),
    );
    if (sticky) return;
    // A notice carrying an action gets longer than one that only reports.
    // Six seconds is enough to read "Left half lost ⌃⌥←"; it is not enough to
    // read it, look up at the two rows it changed, decide, and come back — and
    // the way back from a multi-row change is the last thing that should expire
    // under someone still thinking about it.
    _noticeTimer = Timer(
        visible ??
            (action != null
                ? const Duration(seconds: 10)
                : const Duration(seconds: 6)), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// **Asked, not stolen — and not refused either.**
  ///
  /// Two commands cannot share a chord (duplicate Carbon registrations of one
  /// combination shadow each other unpredictably), so something has to give.
  /// The first answer was to make it the *other* command, silently; the second
  /// was to refuse. Both were wrong in the same way: neither let the person
  /// doing the typing decide.
  ///
  /// So the row keeps listening and the footer names the owner. Pressing the
  /// same combination again takes it; so does the footer's button; anything
  /// else is simply recorded as usual; esc cancels. Whatever is taken is
  /// undoable, which is what makes offering it safe at all.
  Future<void> _commit(
    CommandRef cmd,
    ({int keyCode, int modifiers}) combo,
  ) async {
    final updated = _bindingFor(
      cmd,
    ).copyWith(keyCode: combo.keyCode, modifiers: combo.modifiers);
    final displaced = conflictFor(widget.bindings, updated);

    if (displaced != null && !_isRepeatOf(cmd, combo)) {
      setState(
        () => _pending = (
          row: cmd,
          keyCode: combo.keyCode,
          modifiers: combo.modifiers,
          owner: displaced,
        ),
      );
      _notify(
        '${formatCombo(combo.keyCode, combo.modifiers)} is used by '
        '${_labelFor(displaced)}. Press it again to use it here.',
        actionLabel: 'Use it here',
        // Two ways in, and not for redundancy: [RecordingField] answers every
        // key with `handled`, so Tab cannot walk out to this button. A
        // mouse-only affordance would be a keyboard dead end in the pane whose
        // whole subject is the keyboard — a defect this app has shipped twice.
        action: () async {
          await _endRecordingQuietly();
          _take(cmd, combo, displaced);
        },
        sticky: true,
      );
      return; // still recording
    }

    await _endRecordingQuietly();
    _take(cmd, combo, displaced);
  }

  /// End any recording, and never let *that* failure eat what comes next.
  ///
  /// `_stopRecording` awaits `onCaptureEnd`, a method-channel call that can
  /// reject. Every caller is about to do the thing the user actually asked for
  /// — commit a rebind, run an Undo, clear a row, open the picker — and losing
  /// it because a hotkey *resume* failed is a click that does nothing with
  /// nothing on screen to say why. That is the mistake `_startRecording`
  /// documents above, and it was reported from real use in M10.
  ///
  /// Safe because `_stopRecording` clears its own state **before** awaiting the
  /// channel: by the time this can throw, the pane is already right and only
  /// the re-registration has failed, which the coordinator recovers on its next
  /// apply.
  ///
  /// One helper rather than four `try`/`catch`es: the first review round fixed
  /// exactly one of these call sites and the next round found the other three.
  Future<void> _endRecordingQuietly() async {
    try {
      await _stopRecording();
    } catch (_) {
      // Deliberately swallowed; see above.
    }
  }

  /// Whether [combo] is the confirming second press of the pending question.
  bool _isRepeatOf(CommandRef cmd, ({int keyCode, int modifiers}) combo) {
    final p = _pending;
    // A question is always about the row that is recording — [_startRecording]
    // drops one raised elsewhere and [_stopRecording] drops it outright — so
    // this is stated rather than re-tested. A comparison here would be a branch
    // no input can reach, which is worse than an assertion: it reads as a
    // handled case and is never exercised.
    assert(p == null || p.row == cmd);
    return p != null &&
        p.keyCode == combo.keyCode &&
        p.modifiers == combo.modifiers;
  }

  /// Bind [combo] to [cmd], offering the way back when it costs another row.
  void _take(
    CommandRef cmd,
    ({int keyCode, int modifiers}) combo,
    CommandRef? displaced,
  ) {
    // Snapshotted *before* the rebind: this is the state Undo returns to — and
    // **only the rows this take changes**, never the whole set.
    //
    // A whole-set snapshot silently reverted edits made after it was taken. Its
    // notice lives for ten seconds and nothing here cancels it (a conflict-free
    // rebind raises no `_pending`, so `_startRecording`'s cleanup does not
    // apply), so: take a chord, rebind a third command, click the still-visible
    // Undo — and the third command went back to a binding the user had already
    // replaced. `restoreBindings` reconciles whatever it is handed, keeping
    // every command *not* named at its current value, so scoping this costs
    // nothing but the two lines below.
    final before = [
      _bindingFor(cmd),
      if (displaced != null) _bindingFor(displaced),
    ];
    widget.onRebound(
      _bindingFor(
        cmd,
      ).copyWith(keyCode: combo.keyCode, modifiers: combo.modifiers),
    );
    if (displaced == null) return;
    _notifyDisplaced(displaced, combo, before);
  }

  /// Report what a change cost another row, and offer it back.
  ///
  /// Shared by the list and the region picker, whose Save can displace exactly
  /// the same way. Two implementations of this sentence would drift, and the
  /// drift would be in the one place the user is told what just happened.
  void _notifyDisplaced(
    CommandRef displaced,
    ({int keyCode, int modifiers}) combo,
    List<Binding> before,
  ) {
    // Point at the row, not only at the sentence. It is named at the bottom of
    // the window while sitting anywhere in a list of twelve.
    _flashRow(displaced);
    final restore = widget.onRestoreBindings;
    _notify(
      '${_labelFor(displaced)} lost '
      '${formatCombo(combo.keyCode, combo.modifiers)}.',
      actionLabel: restore == null ? null : 'Undo',
      action: restore == null ? null : () => restore(before),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.mac;
    return Scaffold(
      backgroundColor: t.windowBackground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(t),
          // Above the scroll area, not inside it: a warning you have to scroll
          // to find is not a warning. The list below simply gets less room.
          if (!widget.permissionGranted) _notGrantedNotice(t),
          Expanded(
            child: SingleChildScrollView(
              controller: widget.scrollController,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sectionHeader('Built-in', t),
                    // The row set comes from what *exists* — eleven commands
                    // and N regions — never from what the preferences file
                    // happens to contain. Driving it from `bindings` renders
                    // nothing at all when they have not loaded yet, which is
                    // the blank grey pane this list already shipped once;
                    // `_bindingFor`'s orElse is what makes a missing entry a
                    // row with no shortcut instead.
                    _group(t, [
                      for (final c in ShortcutCommand.values)
                        _flashWrap(
                          BuiltIn(c).jsonName,
                          t,
                          _row(BuiltIn(c), t),
                        ),
                    ]),
                    if (_showRegions) ...[
                      const SizedBox(height: 15),
                      _sectionHeader('Your regions', t),
                      _regionsHint(t),
                      _group(t, [
                        for (final region in widget.regions)
                          _flashWrap(
                            Custom(region.id).jsonName,
                            t,
                            _row(Custom(region.id), t),
                          ),
                        if (widget.onRegionSaved != null) _addRegionRow(t),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _footer(t),
        ],
      ),
    );
  }

  /// Whether the regions group appears at all.
  ///
  /// Absent only when the pane is read-only for regions *and* there are none:
  /// a header over an empty box would announce a feature this pane has no way
  /// to reach.
  bool get _showRegions =>
      widget.onRegionSaved != null || widget.regions.isNotEmpty;

  /// A group title, in the System Settings idiom — above its box, not inside
  /// it. Custom regions were previously rows appended to the eleven built-ins
  /// and styled identically, so the feature was invisible to anyone who had not
  /// already found it.
  ///
  /// A real heading, not just bold small text: without the flag a screen
  /// reader's heading rotor cannot find either group, so the structure this
  /// exists to create is visible only to people who can see it.
  Widget _sectionHeader(String title, MacTokens t) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: t.labelTertiary,
        ),
      ),
    ),
  );

  /// What the regions group is *for*, and the two ways to fill it.
  ///
  /// Shown with and without regions, deliberately. It used to retire with the
  /// first region, but the grid's own ⌘S caption retires at that same moment
  /// (`saveHint` is `regions.isEmpty`), which left the grid-to-shortcut route
  /// taught nowhere for anyone who already had one. "Add region…" is a
  /// labelled button and documents itself; ⌘S is invisible unless told.
  Widget _regionsHint(MacTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      "Bind a shape the built-ins don't cover — draw it here, or select it "
      'in the grid and press ⌘S.',
      style: TextStyle(fontSize: 11, color: t.labelTertiary),
    ),
  );

  /// One rounded group, its rows hairline-separated.
  Widget _group(MacTokens t, List<Widget> rows) => DecoratedBox(
    decoration: BoxDecoration(
      color: t.contentBackground,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: t.separator),
    ),
    child: Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 1, color: t.separator, indent: 52),
          rows[i],
        ],
      ],
    ),
  );

  /// The row to point at, by [CommandRef.jsonName], tinted once.
  ///
  /// Two things need it, and they are the same need. A saved region otherwise
  /// appears at the foot of a twelve-row list with nothing to mark it. And a row
  /// that just *lost* its combination is named in a sentence at the bottom of
  /// the window while sitting ten rows up — the message and the thing it
  /// describes disconnected, which is most of the reason the old silent theft
  /// was so confusing.
  String? _flash;

  /// Bumped per flash, so saving the same region twice restarts the animation.
  /// A [TweenAnimationBuilder] whose key did not change would simply sit at its
  /// end value.
  int _flashNonce = 0;

  /// Whether [_flash]'s row has been scrolled to yet.
  ///
  /// The row does not exist at the moment of saving — `onRegionSaved` returns
  /// before the coordinator has persisted and notified — so the first attempt
  /// finds no context and [didUpdateWidget] retries once the row arrives.
  bool _flashRevealed = false;

  final _rowKeys = <String, GlobalKey>{};

  void _flashRow(CommandRef ref) {
    if (!mounted) return;
    setState(() {
      _flash = ref.jsonName;
      _flashNonce++;
      _flashRevealed = false;
    });
    _scheduleReveal();
  }

  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = _flash;
      if (!mounted || id == null || _flashRevealed) return;
      final ctx = _rowKeys[id]?.currentContext;
      if (ctx == null) return; // not built yet — the next update tries again
      _flashRevealed = true;
      // A no-op in the common case: the window measures its content and grows,
      // so the new row is usually already on screen. It earns its keep once
      // native has clamped the window to the display.
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
      );
    });
  }

  /// [child] under a stable [GlobalKey], pulsing while it is the flashed row.
  ///
  /// The key is the **outermost** node either way, so it never moves in the
  /// tree as the animation comes and goes.
  Widget _flashWrap(String id, MacTokens t, Widget child) {
    final key = _rowKeys.putIfAbsent(id, GlobalKey.new);
    if (_flash != id) return KeyedSubtree(key: key, child: child);
    return KeyedSubtree(
      key: key,
      // A tween, not an `AnimationController`: a window hidden with `orderOut`
      // has no frames to finish an animation with, and this pane has already
      // paid once for a transient that outlived its host. There is nothing here
      // to dispose and nothing to strand.
      child: TweenAnimationBuilder<double>(
        key: ValueKey('flash-$id-$_flashNonce'),
        tween: Tween(begin: 1, end: 0),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        onEnd: () {
          if (mounted && _flash == id) setState(() => _flash = null);
        },
        builder: (_, v, row) => ColoredBox(
          color: t.accent.withValues(alpha: 0.22 * v),
          child: row,
        ),
        child: child,
      ),
    );
  }

  Widget _header(MacTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Shortcuts',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: t.labelPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          // "Its own display", because that is what apply_region.dart does —
          // deliberately, so a shortcut never flings a window to wherever the
          // cursor happens to rest. This line said "the active display" for
          // four milestones, which described the overlay and contradicted the
          // shortcuts it sits above.
          'Open the grid, or snap the frontmost window straight to a '
          'region of its own display.',
          style: TextStyle(fontSize: 12, color: t.labelSecondary),
        ),
      ],
    ),
  );

  /// Why none of the rows below will do anything, and the one way to fix it.
  ///
  /// Deliberately not a disabled-looking list. The bindings are still editable
  /// and still persist — configuring shortcuts before granting is a reasonable
  /// order to do things in, and greying the rows out would say otherwise.
  /// One wrapped line with the remedy inline, not a block with a push button.
  ///
  /// The taller version cost ~120 pt and pushed the last three rows below the
  /// fold — a warning that hides the very list it is warning about. This says
  /// the same thing in a third of the space, and the link is still one click.
  Widget _notGrantedNotice(MacTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 14,
              color: t.warning,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text:
                        'None of these will fire until Orthant has '
                        'Accessibility permission. You can still change '
                        'them.  ',
                  ),
                  // A WidgetSpan so the link wraps with the sentence rather
                  // than claiming a line of its own.
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: MacControl(
                      onPressed: widget.onOpenAccessibility,
                      focusRingRadius: 4,
                      inset: 2,
                      child: Text(
                        'Open Accessibility Settings…',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: t.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: t.labelPrimary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// How much room the footer takes, whatever it is currently saying.
  ///
  /// **Fixed on purpose.** Its contents change constantly — the hint becomes a
  /// notice, an action button comes and goes, *Reset Shortcuts* hides while
  /// recording — and this window measures its content to size itself, so any
  /// change in this row's height resizes the whole window. Measured against the
  /// real app before pinning it: the pane oscillated **752 ↔ 755 pt**, which is
  /// a 3 pt twitch when a notice appears and *another* six seconds later when it
  /// expires. The second is the worse one: the window moves while the user is
  /// doing nothing at all.
  ///
  /// The number is a floor over the tallest state — the bordered *Reset
  /// Shortcuts* button — with room to spare, not a tuned fit. A tuned fit is
  /// what `_heights` already is, and that constant has now gone stale twice;
  /// this one is deliberately loose enough that text metrics cannot invalidate
  /// it. Nothing in the row is centred against it, so slack costs nothing.
  static const _footerHeight = 30.0;

  Widget _footer(MacTokens t) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: SizedBox(
      height: _footerHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              _notice?.message ??
                  (_recording != null
                      ? 'Listening… press a combination, or esc to cancel.'
                      : 'Click a shortcut to change it. '
                            'Combinations need ⌃, ⌥, ⇧ or ⌘.'),
              // Two lines at most, so a long message cannot change the pane's
              // height — this window measures its content to size itself, and a
              // line that grows and collapses drives exactly the resize loop that
              // took three attempts to settle.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: _notice != null ? t.labelPrimary : t.labelTertiary,
              ),
            ),
          ),
          if (_notice case (
            actionLabel: final label?,
            action: final act?,
            message: _,
          )) ...[
            const SizedBox(width: 10),
            MacControl(
              key: const ValueKey('notice-action'),
              onPressed: () async {
                _noticeTimer?.cancel();
                setState(() => _notice = null);
                // A notice outlives the moment that raised it — six seconds is
                // long enough to click another row and start recording — and
                // every one of these actions re-registers the *whole* hotkey set.
                // Firing one mid-capture puts the chords back while the row is
                // still listening, so the next combination is swallowed by its
                // own registration and fires a window move instead of being
                // recorded: the precise defect the suspension exists to prevent.
                //
                // `_ResetButton` beside this one is simply hidden while
                // recording, for the same reason. Ending the recording is the
                // better answer here — the way back stays available.
                await _endRecordingQuietly();
                act();
              },
              semanticLabel: label,
              focusRingRadius: 5,
              child: Text(
                label,
                style: TextStyle(fontSize: 11.5, color: t.accent),
              ),
            ),
          ],
          if (widget.onResetBindings != null && _recording == null) ...[
            const SizedBox(width: 10),
            _ResetButton(tokens: t, onPressed: _resetWithUndo),
          ],
        ],
      ),
    ),
  );

  /// Delete [region], offering it straight back.
  ///
  /// A drawn shape is minutes of somebody's attention and deletion is one
  /// click, so it needs a way back. An undo *notice* rather than a confirm
  /// dialog: confirmation taxes every deletion to protect the rare mistaken
  /// one, and a second modal on top of the sheet that launched it reads badly.
  ///
  /// Undo re-saves the region, so it returns at the end of the list rather than
  /// its old position. That is a visible difference, and the honest trade for
  /// keeping this to the seams that already exist.
  void _deleteWithUndo(CustomRegion region, Binding? binding) {
    final restore = widget.onRegionSaved;
    widget.onRegionDeleted?.call(region.id);
    _notify(
      '${region.name} deleted.',
      actionLabel: restore == null ? null : 'Undo',
      action: restore == null
          ? null
          : () => restore((
                region: region,
                keyCode: binding?.keyCode ?? kUnboundKey,
                modifiers: binding?.modifiers ?? 0,
              )),
    );
  }

  /// Restore every default, offering the previous set straight back.
  ///
  /// One click rewrote eleven-plus bindings with no way back, while deleting a
  /// *single* region has had an Undo since M9 — the larger change was the less
  /// recoverable one. Deliberately an undo rather than a confirmation dialog:
  /// confirmation taxes every use to protect the rare mistaken one, which is
  /// the same argument that kept region deletion undo-based.
  void _resetWithUndo() {
    // Scoped like `_take`, and here the scope is genuinely wide: every row the
    // reset *changes*. A row already sitting at its default is not part of this
    // operation, so an edit made to it afterwards must survive an Undo of a
    // reset that never touched it.
    final before = [
      for (final b in widget.bindings)
        if (b != defaultBindingFor(b.command)) b,
    ];
    final restore = widget.onRestoreBindings;
    widget.onResetBindings!();
    _notify(
      'All shortcuts reset to their defaults.',
      actionLabel: restore == null ? null : 'Undo',
      action: restore == null ? null : () => restore(before),
    );
  }

  /// The last row of the list: create a region.
  ///
  /// A row rather than a footer button, so it reads as the natural end of the
  /// list it extends and lands in the same Tab order as everything above it.
  Widget _addRegionRow(MacTokens t) => MacControl(
        key: const ValueKey('add-region'),
        onPressed: () => _openPicker(null),
        semanticLabel: 'Add region',
        focusRingRadius: 4,
        inset: 0,
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: Icon(Icons.add, size: 16, color: t.accent),
              ),
              const SizedBox(width: 12),
              ExcludeSemantics(
                child: Text(
                  'Add region…',
                  style: TextStyle(fontSize: 13, color: t.accent),
                ),
              ),
            ],
          ),
        ),
      );

  /// Present the picker over the pane.
  ///
  /// A dialog, not an inline expanding row: the settings window measures its
  /// content to size itself, and that code oscillated across six sizes before
  /// it settled. A fixed-size sheet leaves the measured height alone.
  Future<void> _openPicker(CustomRegion? initial, {bool isNew = false}) async {
    final onSaved = widget.onRegionSaved;
    if (onSaved == null) return;
    // Single-flight: one sheet at a time, so the retained route handle always
    // refers to the one that is actually on screen.
    if (_presenting) {
      _queuedPickers.add((initial: initial, isNew: isNew));
      return;
    }
    _presenting = true;
    // Everything below is inside the try, so that **any** throw hands the slot
    // back. `_stopRecording` awaits `onCaptureEnd`, which is a method channel
    // call and can reject; a throw there used to strand `_presenting` at true
    // for the rest of the session, after which "Add region…" and every region's
    // edit control silently did nothing — with no error anywhere, because these
    // callbacks are `VoidCallback`s and the future is unobserved.
    try {
      // A row may still be listening. "Add region…" and a region's name are
      // controls of their own, so clicking either while a row records leaves the
      // recording live *underneath a modal* — the footer goes on saying
      // "Listening…" and the row goes on showing its pill.
      //
      // Not cosmetic, and worse than it looks. The row's recording holds a global
      // hotkey suspension that only `_stopRecording` hands back, and this route's
      // `endCapture` is a no-op unless the *sheet itself* recorded something. So
      // opening the picker over a live recording and then cancelling it left the
      // app with **every shortcut dead** until the user happened to press esc on
      // a row they had stopped looking at.
      //
      // Exactly the M5 and M10 defect once more, on a third path: recording
      // suspends, and the thing that resumes has to be reached by every way out.
      //
      // Found by driving the real app; no test reached it, because none of them
      // opened the picker with a row already recording.
      //
      // `_stopRecording` is idempotent, so this costs nothing when no row is
      // recording. `_presenting` is already set, so the await cannot let a ⌘S
      // handoff in beside this one.
      //
      // Its failure must not take the sheet with it. `_stopRecording` clears the
      // recording state *before* awaiting the channel, so by the time this can
      // throw the UI is already right and only the hotkey resume has failed —
      // which the coordinator recovers on its next apply. Gating the sheet on
      // that round trip is the mistake `_startRecording` documents two hundred
      // lines up: a click that does nothing at all, with nothing on screen to
      // say why.
      await _endRecordingQuietly();
      if (!mounted) return;

      // A shape from ⌘S has an id but no row yet, so it has no binding to carry
      // in and its sheet must offer Add rather than Delete.
      final binding = (initial == null || isNew)
          ? null
          : _bindingFor(Custom(initial.id));

      // The *route* owns the suspend/resume, not the sheet.
      //
      // Recording suspends every global hotkey, and only _stopRecording resumed
      // them — while Cancel, Save, Delete, Esc and a tap on the barrier all pop
      // the route without going through it. Recording then cancelling therefore
      // left the app with **no working shortcuts at all** until something else
      // happened to re-register them. The settings *window* had this exact defect
      // fixed once already (M5: "revives the hotkeys a close mid-recording had
      // left unregistered"); the sheet reintroduced it on a new path.
      //
      // `suspended` makes the resume idempotent, so the sheet's own
      // _stopRecording and the backstop below cannot double-fire.
      var suspended = false;
      Future<void> startCapture() async {
        suspended = true;
        await widget.onCaptureStart?.call();
      }

      Future<void> endCapture() async {
        if (!suspended) return;
        suspended = false;
        await widget.onCaptureEnd?.call();
      }

      // Pushed as a route we keep, rather than through `showDialog`, so that
      // [dispose] can call `removeRoute` — which is **immediate**. Popping is not:
      // a popped `TransitionRoute` keeps its overlay entries until the reverse
      // transition finishes, and a window hidden with `orderOut` has no frames to
      // finish it with, so the sheet stayed fully rendered and would have faded
      // out over the *next* open. `removeRoute` runs no animation and still
      // completes the pushed route's future, so `endCapture` below still fires.
      final navigator = Navigator.of(context, rootNavigator: true);
      final route = DialogRoute<void>(
        context: context,
        settings: const RouteSettings(name: _pickerRoute),
        barrierColor: const Color(0x33000000),
        // 100 ms, not Material's 150. Nothing is *loading* behind this sheet —
        // there is no persistence, hotkey or native call on the way in — so the
        // whole delay between *Add region…* and a usable grid is the transition
        // itself, and it read as weight the app does not have. 100 ms is the
        // overlay's own entrance, tuned by hand against the same expectation.
        //
        // Zero when the system asks for reduced motion. The first place in this
        // app to honour that; the overlay's fade should follow.
        animationStyle: AnimationStyle(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 100),
        ),
        // `showDialog`'s default, and part of what makes a dialog modal to the
        // keyboard: Tab wraps inside the sheet instead of walking out into the
        // pane behind it. Pushing the route by hand means opting back in.
        traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        // What `showDialog` does for us, kept because it is doing real work: the
        // sheet is built under the navigator, not under this pane.
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        builder: (dialogContext) => RegionPickerSheet(
          initial: initial,
          isNew: isNew,
          initialKeyCode: binding?.keyCode ?? kUnboundKey,
          initialModifiers: binding?.modifiers ?? 0,
          gridCols: widget.gridCols,
          gridRows: widget.gridRows,
          onCaptureStart: startCapture,
          onCaptureEnd: endCapture,
          conflictName: (keyCode, modifiers) {
            final ref = initial == null ? null : Custom(initial.id);
            final clash = conflictFor(
              widget.bindings,
              Binding(ref ?? const Custom('__new__'), keyCode, modifiers),
            );
            return clash == null ? null : _labelFor(clash);
          },
          onCancel: () => Navigator.of(dialogContext).pop(),
          onSubmit: (draft) {
            Navigator.of(dialogContext).pop();
            // The sheet can displace exactly as a row can — its Save is
            // enabled once the user accepts the collision — so the same
            // sentence and the same way back are raised from here. Computed
            // *before* the save, which is what performs the displacement, and
            // scoped to the two rows it can change for the reason `_take`
            // gives. For a region being created, the first of these is the
            // `orElse` unbound row, which is exactly what Undo should put back.
            final displaced = conflictFor(
              widget.bindings,
              Binding(Custom(draft.region.id), draft.keyCode, draft.modifiers),
            );
            final before = [
              _bindingFor(Custom(draft.region.id)),
              if (displaced != null) _bindingFor(displaced),
            ];
            onSaved(draft);
            _flashRow(Custom(draft.region.id));
            if (displaced != null) {
              _notifyDisplaced(displaced, (
                keyCode: draft.keyCode,
                modifiers: draft.modifiers,
              ), before);
            }
          },
          onDelete: (initial == null || isNew)
              ? null
              : () {
                  Navigator.of(dialogContext).pop();
                  _deleteWithUndo(initial, binding);
                },
        ),
      );
      _pickerRouteRef = route;
      // Ownership ends when the route is **gone**, on its own continuation.
      //
      // Sequencing this behind the hotkey restore ended it at
      // `max(resumed, gone)` instead: a restore slower than the 150 ms exit left
      // the handle pointing at a route that had already left the navigator's
      // history, and a close in that window sent the teardown to `finalizeRoute`
      // on it — an assertion in debug, an invalid history index in release.
      //
      // Identity-checked, because a queued picker may own the slot by then.
      final gone = route.completed.then<void>((_) {
        if (identical(_pickerRouteRef, route)) _pickerRouteRef = null;
      });

      await navigator.push(route);
      // Resume the global hotkeys the moment the route is **popped**, which is
      // when that future completes. Waiting for `completed` instead put the resume
      // behind the route's disposal, and Flutter defers that until the overlay
      // subtree unmounts — another frame, the one resource a hidden window does
      // not have. A frame-starved close after a recording therefore left every
      // shortcut suspended until the next open. The coordinator's own close
      // backstop hid it; the guarantee this route owns did not hold.
      //
      // Started, not awaited: prompt, but unable to hold ownership open behind it.
      final restored = endCapture();
      // `Future.wait` attaches to both immediately. Awaiting them in sequence
      // left `restored` unobserved for the length of `await gone`, so a restore
      // that failed in that window was reported as an uncaught async error —
      // and then again when the await finally reached it.
      await Future.wait<void>([gone, restored]);
    } finally {
      _presenting = false;
      // **Inside** the finally. `endCapture()` above is a second reachable
      // throw on the same channel, and a throw that skipped this drain
      // silently dropped the shape ⌘S was pressed to keep — the exact loss the
      // queue exists to prevent, one level down. `_presenting` is released
      // first, so the recursive call is admitted.
      await _drainQueuedPicker();
    }
  }

  /// Show the next shape ⌘S handed over while a sheet was up.
  ///
  /// Presentation waits for `completed` — the route above must be *gone*, not
  /// merely popped, before another is pushed.
  Future<void> _drainQueuedPicker() async {
    if (_queuedPickers.isEmpty || !mounted) return;
    final next = _queuedPickers.removeAt(0);
    await _openPicker(next.initial, isNew: next.isNew);
  }

  Widget _row(CommandRef cmd, MacTokens t) {
    final binding = _bindingFor(cmd);
    final custom = _customOf(cmd);
    final isRecording = _recording == cmd;
    // Focus counts as hover for the clear affordance.
    final isHovered =
        _hovered == cmd || _focused == cmd || _readerOn == cmd;

    return MouseRegion(
      // Hover stays on its own MouseRegion rather than moving to
      // FocusableActionDetector's callback: that callback did not fire for this
      // row, and what it drives — the only way to clear a binding — is too
      // load-bearing to gamble on.
      onEnter: (_) => setState(() => _hovered = cmd),
      onExit: (_) => setState(() => _hovered = null),
      child: MacControl(
        onPressed: isRecording ? null : () => _startRecording(cmd),
        // The whole point of the row: what it does, and what it is bound to.
        // The pending question has to be *here*, not only in the footer.
        //
        // The footer is a plain Text with no live region, the warning-coloured
        // pill is inside ExcludeSemantics, and RecordingField answers every key
        // with `handled` so Tab cannot reach "Use it here". A screen-reader user
        // pressing an occupied combination would otherwise get silence and no
        // way forward but esc — the six-interaction dead end this whole change
        // exists to remove, restored for exactly one class of user.
        semanticLabel: switch ((isRecording, _pending)) {
          (true, final p?) when p.row == cmd =>
            '${_labelFor(cmd)}, ${formatCombo(p.keyCode, p.modifiers)} is '
                'used by ${_labelFor(p.owner)}. '
                'Press it again to use it here, or escape to cancel.',
          (true, _) => '${_labelFor(cmd)}, listening for a combination',
          _ =>
            '${_labelFor(cmd)}, ${binding.isBound ? formatCombo(binding.keyCode, binding.modifiers) : "no shortcut"}'
                '${widget.unavailable.contains(cmd) ? ", unavailable" : ""}',
        },
        // The clear button lives inside this row and must stay reachable; the
        // decorative halves below exclude themselves instead.
        containsControl: true,
        // Focus reveals the clear button exactly as hover does. Without this the
        // affordance is mouse-only, and clearing a shortcut was unreachable by
        // keyboard entirely — in the pane whose whole subject is the keyboard.
        onFocusChange: (f) => setState(() => _focused = f ? cmd : null),
        // And a screen reader's cursor counts too, on its own track: it moves
        // independently of keyboard focus, so revealing on `onFocusChange`
        // alone left the button absent for anyone driving by VoiceOver — the
        // button existed, was correctly labelled, and was never built.
        onAccessibilityFocusChange: (f) =>
            setState(() => _readerOn = f ? cmd : null),
        focusRingRadius: 4,
        inset: 0,
        child: Container(
          color: isHovered && !isRecording
              ? t.rowHighlight
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              // Null for the summon, which draws a lattice: it opens the grid
              // rather than placing a window anywhere in particular.
              // For a custom row the glyph belongs *inside* the edit
              // affordance below, not beside it: the design says "the glyph or
              // the name", and the glyph is the larger, more obvious target.
              // Left out here it inherited the row's own action and started
              // *recording* instead of opening the picker.
              if (custom == null) ...[
                RegionGlyph(
                  command: _regionOf(cmd),
                  dimmed: !binding.isBound,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: custom == null
                    ? ExcludeSemantics(
                        child: Text(
                          _labelFor(cmd),
                          style: TextStyle(fontSize: 13, color: t.labelPrimary),
                        ),
                      )
                    // A custom row's name opens the picker: that is where its
                    // shape is changed and where Delete lives. Putting a second
                    // hover affordance beside the clear button instead would
                    // crowd a row whose one control has already been the
                    // subject of a VoiceOver defect.
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: MacControl(
                          key: ValueKey('edit-${cmd.jsonName}'),
                          onPressed: () => _openPicker(custom),
                          semanticLabel: 'Edit ${custom.name}',
                          focusRingRadius: 4,
                          inset: 2,
                          child: Row(
                            children: [
                              RegionGlyph(
                                custom: custom,
                                dimmed: !binding.isBound,
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  _labelFor(cmd),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: t.labelPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // The one place this row's two actions are
                              // visible: its glyph and name edit the region,
                              // everything right of them records a shortcut.
                              // Nothing said so, and a split you cannot see is
                              // a split nobody finds.
                              //
                              // Faded rather than inserted, so the space is
                              // reserved whether it shows or not. This pane's
                              // measured height sizes the *window*, and a row
                              // whose metrics move on hover would ask the
                              // window to resize under the pointer — the twitch
                              // the fixed-height footer was introduced to stop.
                              Opacity(
                                opacity: isHovered && !isRecording ? 1 : 0,
                                child: Icon(
                                  Icons.edit_outlined,
                                  size: 12,
                                  color: t.labelSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              if (isRecording)
                ExcludeSemantics(
                  child: RecordingField(
                    // The combination in question, on the row it was pressed
                    // on, so the footer's sentence has a visible subject.
                    pending: _pending?.row == cmd
                        ? (
                            keyCode: _pending!.keyCode,
                            modifiers: _pending!.modifiers,
                          )
                        : null,
                    onCombo: (combo) => _commit(cmd, combo),
                    onCancel: _stopRecording,
                  ),
                )
              else ...[
                if (binding.isBound && widget.unavailable.contains(cmd))
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Tooltip(
                      message:
                          'macOS or another app already uses this '
                          'combination, so it never reaches Orthant.\n'
                          'Click the shortcut to pick a different one.',
                      // The row's label already ends in ", unavailable"; the
                      // icon is how the same thing is said to a sighted user.
                      excludeFromSemantics: true,
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: t.warning,
                      ),
                    ),
                  ),
                ExcludeSemantics(
                  // A bound row shows its keycaps; an unbound one shows a
                  // *button*.
                  //
                  // "Not set" was grey status text, and on a row whose entire
                  // purpose is to be clicked a status reads as a verdict: a
                  // user whose shortcut had been displaced concluded the row
                  // could not be set at all, and said so twice. Every other row
                  // carries something that looks pressable — the keycaps — so
                  // the one row that needs pressing most was the only one that
                  // looked inert.
                  child: binding.isBound
                      ? KeycapRow(
                          keyCode: binding.keyCode,
                          modifiers: binding.modifiers,
                        )
                      : SetShortcutPill(
                          label: 'Click to set',
                          hovered: isHovered,
                        ),
                ),
                SizedBox(
                  width: 22,
                  // Present for every bound row, shown only for the one being
                  // pointed at. Making its *existence* depend on focus put it
                  // out of a screen reader's reach: Flutter's macOS bridge
                  // dispatches `didLoseAccessibilityFocus` to the row before it
                  // records the newly focused node
                  // (`AccessibilityBridge::SetLastFocusedId`), so a cursor
                  // moving from the row onto this button deleted the button on
                  // its way. Reveal-on-focus cannot survive that ordering; being
                  // resident does not have to.
                  child: binding.isBound
                      ? Visibility(
                          key: ValueKey('clear-${cmd.jsonName}'),
                          visible: isHovered,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          // The whole point: in the tree even while invisible.
                          // `maintainFocusability` stays false, so it is not a
                          // Tab stop until it is on screen — eleven hidden ones
                          // would be eleven dead stops.
                          maintainSemantics: true,
                          // Required, not incidental: without it `Visibility`
                          // wraps the child in an `IgnorePointer`, which takes
                          // the tap action off the node and leaves a button a
                          // reader can read and not press — the exact defect
                          // being fixed. Safe because an invisible one is also
                          // un-hovered, and a pointer must enter the row (which
                          // reveals it) before it can click anything here.
                          maintainInteractivity: true,
                          child: _ClearButton(
                            tokens: t,
                            command: _labelFor(cmd),
                            // Ends a recording first, like every other control
                            // in this pane that re-registers the hotkey set.
                            // Hover reveals this button on *any* row, so it is
                            // reachable while a different row is listening —
                            // and `onRebound` re-registers everything, putting
                            // the chords back under a live recorder.
                            onPressed: () async {
                              await _endRecordingQuietly();
                              widget.onRebound(Binding.unbound(cmd));
                            },
                          ),
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({
    required this.tokens,
    required this.command,
    required this.onPressed,
  });
  final MacTokens tokens;

  /// Named in the label because these are now resident: a screen reader can
  /// meet eleven of them, and "Remove shortcut" on its own says which one only
  /// if you happen to have heard the row first.
  final String command;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: 'Remove shortcut',
        waitDuration: const Duration(milliseconds: 500),
        excludeFromSemantics: true, // MacControl announces it
        child: MacControl(
          onPressed: onPressed,
          semanticLabel: 'Remove $command shortcut',
          focusRingRadius: 8,
          inset: 1,
          child: Icon(Icons.cancel, size: 15, color: tokens.labelTertiary),
        ),
      ),
    );
  }
}

/// Restore every shortcut to its default. Hidden while recording, so it cannot
/// be hit by the click that was meant to land on a row.
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.tokens, required this.onPressed});
  final MacTokens tokens;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MacControl(
      onPressed: onPressed,
      focusRingRadius: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: tokens.contentBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tokens.keycapBorder),
        ),
        child: Text(
          'Reset Shortcuts',
          style: TextStyle(fontSize: 12.5, color: tokens.labelPrimary),
        ),
      ),
    );
  }
}
