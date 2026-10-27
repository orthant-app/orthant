import 'package:flutter/gestures.dart'
    show EagerGestureRecognizer, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../overlay/grid_selection.dart';
import '../core/key_chord.dart';
import '../core/key_words.dart';
import '../l10n/app_localizations.dart';
import '../l10n/strings.dart';
import '../shortcuts/bindings.dart';
import '../shortcuts/custom_region.dart';
import 'keycap.dart';
import 'keyboard_labels.dart';
import 'mac_control.dart';
import 'platform_theme.dart';
import 'recording_field.dart';

/// What the sheet hands back: the region, plus the combo to bind it to.
///
/// The combo travels with the region rather than being applied separately so
/// that creating a shortcut is one transaction. Two steps would let a region
/// exist for a moment with no way to fire it, which is the state the list would
/// then have to explain.
typedef RegionDraft = ({CustomRegion region, KeyChord? chord});

/// Draw a region, name it, bind it.
///
/// Presented as a sheet over the pane rather than inline. The settings window
/// measures its content to size itself, and that code took three attempts and
/// oscillated across six sizes before it settled; a fixed-size sheet leaves the
/// measured height alone, where a row that grows and collapses drives exactly
/// the loop that misbehaved.
class RegionPickerSheet extends StatefulWidget {
  const RegionPickerSheet({
    super.key,
    this.initial,
    this.initialChord,
    required this.gridCols,
    required this.gridRows,
    required this.onSubmit,
    required this.onCancel,
    this.onDelete,
    this.onCaptureStart,
    this.onCaptureEnd,
    this.conflictName,
    this.isNew = false,
  });

  /// Whether this region is being created rather than edited, even though
  /// [initial] is filled in. ⌘S on the grid hands over a complete shape that
  /// has no row yet — so the sheet must offer *Add*, not *Save*, and must not
  /// offer to delete something that does not exist.
  final bool isNew;

  /// The display name of the command already using a combo, or null if it is
  /// free. A callback rather than the bindings list, so the sheet needs to know
  /// nothing about [CommandRef] or how rows are labelled.
  ///
  /// Warning *before* the combo is committed is the point. The list rows can
  /// only report a theft afterwards, in a snackbar, because a row has nowhere
  /// to put a sentence; this sheet does.
  final String? Function(KeyChord chord)? conflictName;

  /// The region being edited, or null to create a new one.
  final CustomRegion? initial;
  final KeyChord? initialChord;

  /// The grid a *new* region is drawn on — the user's live overlay grid.
  ///
  /// There is no control for it here: one grid concept, set in one place. A
  /// region records whatever it was drawn on, so changing the overlay grid
  /// later cannot reinterpret it. An existing region is edited on its own
  /// denominators instead, which [_cols] explains.
  final int gridCols;
  final int gridRows;

  final void Function(RegionDraft) onSubmit;
  final VoidCallback onCancel;

  /// Absent when creating: there is nothing yet to delete.
  final VoidCallback? onDelete;

  /// Suspend / resume the global hotkeys around recording — without this the
  /// combo being recorded also *fires*, so a window jumps mid-capture.
  final Future<void> Function()? onCaptureStart;
  final Future<void> Function()? onCaptureEnd;

  @override
  State<RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<RegionPickerSheet> {
  /// The denominators this region is expressed in — **fixed for the life of
  /// the sheet**.
  ///
  /// There is deliberately no control for these. One grid concept, set in one
  /// place: a second pair of Columns/Rows steppers here looked like a copy of
  /// the General pane and asked the user to reason about a distinction they
  /// should never have to learn. Someone who wants thirds on a 4 × 4 grid sets
  /// General to 6 once, authors the region, and sets it back — the region keeps
  /// its own denominators forever, so that detour leaves no residue.
  ///
  /// Editing uses the *region's* numbers, not the live grid's: reinterpreting a
  /// 3 × 1 region on a 6 × 6 grid would change the shape under the user.
  /// The region as it will be *edited* — refined onto a finer grid where that
  /// can be done without moving it. See [refineForEditing].
  late final CustomRegion? _editing = widget.initial == null
      ? null
      : refineForEditing(widget.initial!,
          gridCols: widget.gridCols, gridRows: widget.gridRows);

  late final int _cols = _editing?.cols ?? widget.gridCols;
  late final int _rows = _editing?.rows ?? widget.gridRows;

  late Cell? _anchor = switch (_editing) {
    null => null,
    final e => Cell(e.c0, e.r0),
  };
  late Cell? _focus = switch (_editing) {
    null => null,
    final e => Cell(e.c1, e.r1),
  };


  /// The name field. Its first text is written in [didChangeDependencies], not
  /// here, because a generated name is shown in the language the sheet is in
  /// and only the context knows that.
  final TextEditingController _name = TextEditingController();

  /// The strings the field was last written with. A change of language, as
  /// opposed to any other dependency changing, is what moves a generated name.
  AppLocalizations? _l10n;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l = context.l10n;
    final before = _l10n;
    _l10n = l;
    if (before == null) {
      final initial = widget.initial;
      if (initial != null) _name.text = regionDisplayName(initial, l);
    } else if (before.localeName != l.localeName) {
      _resuggest();
    }
  }

  /// Whether the name is the user's own words rather than a suggestion.
  ///
  /// Not simply "are we editing". Treating every existing region's name as
  /// authored meant reshaping one never re-suggested, so a region renamed
  /// nothing and reshaped to a third still called itself "Left ⅔" — a row
  /// lying about what it does. The stored data already distinguishes the two
  /// cases: if the name still equals the English suggestion for the stored
  /// shape ([isGeneratedName]), it was generated, so keep generating.
  ///
  /// **The single source of that status.** Set here from the stored name, set
  /// by any edit of the field, and never derived from the field's text: the
  /// field shows the suggestion in the current language, so comparing it to
  /// anything would take a name the user wrote (`左 ⅔`, for a left two-thirds)
  /// for a generated one the moment it matched. Save writes the English
  /// suggestion when this is false and the field exactly when it is true.
  late bool _nameEdited =
      widget.initial != null && !isGeneratedName(widget.initial!);

  late KeyChord? _chord = widget.initialChord;
  bool _recording = false;

  /// Why the last key pressed while recording could not be used, if it could
  /// not (`RecordingField.onRefused`); gone with the recording.
  String? _refusal;

  /// The cell the pointer went down on — the drag's true anchor.
  Cell? _pressCell;

  /// The pointer that went down last, the only one whose moves draw.
  int? _pressPointer;

  /// Whether the grid holds keyboard focus, so it can draw a ring. Without one
  /// a keyboard user tabs into it, sees nothing change, and then finds the
  /// arrows working for no visible reason.
  // ignore: prefer_final_fields  -- written from onFocusChange
  bool _gridFocused = false;

  /// Holds focus for the sheet as a whole, so [CallbackShortcuts] stays in the
  /// key routing. Re-claimed when a recording ends, because the recorder's node
  /// is disposed with it and focus would otherwise land nowhere.
  final _anchorNode = FocusNode(
    debugLabel: 'region-sheet',
    skipTraversal: true,
  );

  static const Size _gridSize = Size(264, 168);

  @override
  void dispose() {
    _name.dispose();
    _anchorNode.dispose();
    super.dispose();
  }

  CellBlock? get _block =>
      (_anchor == null || _focus == null) ? null : blockFrom(_anchor!, _focus!);

  bool get _creating => widget.initial == null || widget.isNew;

  /// Whether the user has explicitly accepted taking the combination from
  /// whoever holds it.
  ///
  /// Cleared whenever the combination changes, so accepting one collision can
  /// never silently cover the next.
  bool _takeAnyway = false;

  /// Saving is blocked while the combo belongs to something else — *until the
  /// user says to take it*.
  ///
  /// Two commands cannot share a chord (duplicate Carbon registrations of one
  /// combination shadow each other unpredictably), so something has to give.
  /// This sheet has been through both wrong answers: it warned and then took it
  /// silently, then it refused. Refusing is the worse of the two here, because
  /// the sheet is *modal over the list* the user would have to go and clear —
  /// a dead end that covers its own way out. Same rule as the shortcuts list,
  /// and the same undo behind it.
  ///
  /// Not while a combination is being recorded: the shortcut on screen is not
  /// the one being typed, so saving there would persist something the user was
  /// in the middle of replacing. Return has always refused mid-recording; the
  /// button did not, which made the mouse and the keyboard disagree in the pane
  /// whose subject is the keyboard.
  bool get _canSubmit =>
      !_recording &&
      _block != null &&
      _name.text.trim().isNotEmpty &&
      (_conflict == null || _takeAnyway);

  /// The command this combo would displace, or null.
  String? get _conflict {
    final chord = _chord;
    return chord == null ? null : widget.conflictName?.call(chord);
  }

  void _select(Cell anchor, Cell focus) {
    // A pan update arrives on **every pointer move** — well over a hundred a
    // second on a trackpad — while the *cell* under the pointer changes a
    // handful of times in a whole drag. Without this guard every one of those
    // moves rebuilt the entire sheet and rewrote the name field.
    if (anchor == _anchor && focus == _focus) return;
    setState(() {
      _anchor = anchor;
      _focus = focus;
      _resuggest();
    });
  }

  /// Re-derive the suggested name from whatever the shape is *now*.
  ///
  /// The name has to follow the shape or it lies about it: a region called
  /// "Left ⅔" that places a third is worse than one with no name at all.
  void _resuggest() {
    if (_nameEdited) return;
    final b = _block;
    if (b == null) return;
    // Not guarded against writing the same string: `TextEditingController`
    // extends `ValueNotifier`, which already drops an equal value, so a
    // `_name.text != suggested` check saves nothing and cannot be shown to.
    // The redundancy worth removing was one level up, in [_select].
    _name.text = localizedSuggestion(
      suggestRegion(
        cols: _cols,
        rows: _rows,
        c0: b.c0,
        c1: b.c1,
        r0: b.r0,
        r1: b.r1,
      ),
      _l10n!,
    );
  }

  KeyEventResult _onGridKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => GridDirection.left,
      LogicalKeyboardKey.arrowRight => GridDirection.right,
      LogicalKeyboardKey.arrowUp => GridDirection.up,
      LogicalKeyboardKey.arrowDown => GridDirection.down,
      _ => null,
    };
    // Only arrows are consumed, so Tab still traverses out of the grid.
    if (direction == null) return KeyEventResult.ignored;
    final next = moveSelectionFor(
      anchor: _anchor,
      focus: _focus,
      direction: direction,
      extend: HardwareKeyboard.instance.isShiftPressed,
      cols: _cols,
      rows: _rows,
    );
    _select(next.anchor, next.focus);
    return KeyEventResult.handled;
  }

  Future<void> _startRecording() async {
    await widget.onCaptureStart?.call();
    if (!mounted) return;
    setState(() {
      _recording = true;
      _refusal = null;
    });
  }

  /// End the recording, applying [combo] if one was pressed.
  ///
  /// **The combination is applied before the channel is awaited**, in the one
  /// `setState` that also takes the recorder down. Assigning it afterwards left
  /// a window the length of a hotkey resume in which the sheet was no longer
  /// recording but still held the *old* shortcut — with Save live — so a quick
  /// Save persisted the combination the user had just replaced. And a resume
  /// that rejected dropped the new combination outright *and* surfaced as an
  /// uncaught async error, because [RecordingField] calls this from a
  /// synchronous key handler with nothing to catch the future it returns.
  ///
  /// The same invariant the list states from the other side: `_stopRecording`
  /// there clears its own state before awaiting, and `_endRecordingQuietly`
  /// swallows whatever the channel does next. This is the fifth call site in
  /// that family — *a failed hotkey resume must never eat what the user just
  /// did* is a property of every one of them, not of the one where it was
  /// noticed.
  Future<void> _stopRecording({KeyChord? combo}) async {
    if (mounted) {
      setState(() {
        if (combo != null) {
          _chord = combo;
          // A new combination is a new question: carrying the acceptance over
          // would let a second collision be taken without ever having been
          // shown.
          _takeAnyway = false;
        }
        _recording = false;
        _refusal = null;
      });
      // The recorder's node goes with it, so take focus back or the sheet is
      // left with none and Return reaches nobody.
      _anchorNode.requestFocus();
    }
    try {
      await widget.onCaptureEnd?.call();
    } catch (_) {
      // Deliberately swallowed. By here the sheet is already correct and only
      // the re-registration failed, which the coordinator recovers on its next
      // apply; letting it out would take the recorded combination with it.
    }
  }

  void _submit() {
    final b = _block!;
    // Renaming or rebinding must not rewrite how the shape is stored. The
    // refined grid is only persisted once the geometry has actually moved,
    // so an unrelated edit leaves the preferences byte-for-byte as they were.
    // Compared against the refined region rather than a captured snapshot: a
    // `late final` initialised from `_block` would have been evaluated on first
    // *read* — inside this method, after the drag — and so always matched.
    final opened = _editing;
    final untouched = opened != null &&
        b.c0 == opened.c0 &&
        b.c1 == opened.c1 &&
        b.r0 == opened.r0 &&
        b.r1 == opened.r1;
    // What is stored: the user's words as typed, or for a generated name the
    // English suggestion for the shape as it ends up, whatever language the
    // field showed. The field's text is not consulted for the second.
    final name = _nameEdited
        ? _name.text.trim()
        : suggestRegionName(
            cols: _cols,
            rows: _rows,
            c0: b.c0,
            c1: b.c1,
            r0: b.r0,
            r1: b.r1,
          );
    widget.onSubmit((
      // Nothing drawn: stored byte-for-byte as it was, only renamed, so an
      // unrelated edit leaves the preferences alone. Drawn or reshaped: stored
      // on the grid it was worked on, which is the grid its row glyph paints.
      //
      // Which grid that is no longer affects *where the window goes* —
      // `gapForPlacement` measures the block rather than the denominators — so
      // the refined grid landing in storage is untidy at worst.
      region: untouched
          ? widget.initial!.copyWith(name: name)
          : CustomRegion(
              id: widget.initial?.id ?? _newId(),
              name: name,
              cols: _cols,
              rows: _rows,
              c0: b.c0,
              c1: b.c1,
              r0: b.r0,
              r1: b.r1,
            ),
      chord: _chord,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = context.l10n;
    return Center(
      // Scrolls in a window shorter than the sheet: on Windows the window's
      // floor gives way to a short screen's work area (a 768-pixel screen at
      // 200 % leaves about 300 points), and Save sat below the bottom edge.
      // A sheet that fits takes no drag, so the grid keeps every one. The
      // margin is outside the scroll view because a Scrollable hit-tests as
      // opaque over its padding too, which hid it from the route's barrier.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SingleChildScrollView(
          // Its own Material, because the sheet is presented in a dialog route
          // with no Scaffold above it — and a TextField without one throws at
          // build time, which in a Release build is a featureless grey box
          // rather than an error anybody can read.
          child: Material(
            type: MaterialType.transparency,
            // Return is the default button, as it is in every macOS dialog —
            // but only when nothing is listening for a combination, because
            // ⌃⌥↩ is a perfectly ordinary shortcut to want to record (it is
            // Maximize's default).
            // CallbackShortcuts must be an ANCESTOR of the focused node: key
            // events travel *up* the focus chain, so a shortcut widget nested
            // below the node that holds focus is simply never on the path.
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): () {
                  if (_canSubmit) _submit();
                },
                const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
                  if (_canSubmit) _submit();
                },
              },
              // And an anchor below it, so the subtree always holds focus. With
              // nothing focused — after a recording is cancelled, say — Return
              // would reach nobody. skipTraversal keeps it out of the Tab
              // order.
              child: Focus(
                focusNode: _anchorNode,
                autofocus: true,
                skipTraversal: true,
                child: Container(
                  width: 344,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    color: t.windowBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.separator),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _creating
                            ? l.regionSheetTitleNew
                            : l.regionSheetTitleEdit,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.labelPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _grid(t),
                      const SizedBox(height: 6),
                      Text(
                        l.regionSheetHint(KeyWords.current.shiftName),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: t.labelTertiary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _nameField(t),
                      const SizedBox(height: 10),
                      _shortcutRow(t),
                      if (_conflict != null) _conflictNotice(t),
                      if (_refusal != null) _refusalNotice(t, _refusal!),
                      const SizedBox(height: 16),
                      _buttons(t),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(PlatformTokens t) {
    return Focus(
      onKeyEvent: _onGridKey,
      onFocusChange: (f) => setState(() => _gridFocused = f),
      child: Builder(
        builder: (context) {
          final focusNode = Focus.of(context);
          return Center(
            // The pointer handling sits *inside* the sized box, so localPosition
            // is already grid-local. Wrapping the centred box instead means every
            // offset carries the centring inset, and cells read a column or two
            // left of where they were clicked.
            child: SizedBox(
              key: const ValueKey('region-grid'),
              width: _gridSize.width,
              height: _gridSize.height,
              // A raw Listener for the press and the drag, not
              // GestureDetector's onTapDown or onPanUpdate. Both are
              // arena-mediated: onTapDown may never fire when a pan is
              // competing, and a pan is recognised only once it has moved, so
              // a press near a cell edge anchored the selection to the
              // neighbouring cell. The grid also claims the pointer at once
              // (an EagerGestureRecognizer): when the window is too short for
              // the sheet, its scroll view would otherwise take a finger's or
              // a pen's vertical drag that started here. A trackpad's
              // two-finger scroll is no press, and still scrolls it. Moves
              // draw only for the pressing pointer's primary button or
              // contact, as the pan they replaced did.
              child: RawGestureDetector(
                gestures: {
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    focusNode.requestFocus();
                    final c = _cellAt(e.localPosition);
                    _pressCell = c;
                    _pressPointer = e.pointer;
                    _select(c, c);
                  },
                  onPointerMove: (e) {
                    final anchor = _pressCell;
                    if (anchor == null) return;
                    if (e.pointer != _pressPointer ||
                        (e.buttons & kPrimaryButton) == 0) {
                      return;
                    }
                    _select(anchor, _cellAt(e.localPosition));
                  },
                  child: CustomPaint(
                    // A *foreground* ring drawn outside the cells, so nothing
                    // in the grid's layout moves when focus arrives — the same
                    // treatment MacControl gives every other control here.
                    foregroundPainter: _gridFocused
                        ? FocusRingPainter(tokens: t, radius: 3, inset: 3)
                        : null,
                    painter: _PickerGridPainter(
                      cols: _cols,
                      rows: _rows,
                      block: _block,
                      cell: t.glyphOutline,
                      fill: t.accent,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Cell _cellAt(Offset local) =>
      pointToCell(local, _gridSize, cols: _cols, rows: _rows);

  Widget _nameField(PlatformTokens t) => Row(
    children: [
      SizedBox(
        width: 62,
        child: Text(
          context.l10n.regionSheetName,
          style: TextStyle(fontSize: 12, color: t.labelSecondary),
        ),
      ),
      Expanded(
        child: TextField(
          controller: _name,
          onChanged: (_) => setState(() => _nameEdited = true),
          style: TextStyle(fontSize: 12.5, color: t.labelPrimary),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 7,
            ),
            filled: true,
            fillColor: t.contentBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: t.keycapBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: t.keycapBorder),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _shortcutRow(PlatformTokens t) => Row(
    children: [
      SizedBox(
        width: 62,
        child: Text(
          context.l10n.regionSheetShortcut,
          style: TextStyle(fontSize: 12, color: t.labelSecondary),
        ),
      ),
      Expanded(
        child: _recording
            ? RecordingField(
                verticalPadding: 4,
                onCombo: (combo) => _stopRecording(combo: combo),
                onCancel: _stopRecording,
                onRefused: (why) => setState(() => _refusal = why),
              )
            : MacControl(
                key: const ValueKey('region-record'),
                onPressed: _startRecording,
                semanticLabel: switch (_chord) {
                  null => context.l10n.regionSheetRecordNone,
                  final chord => context.l10n.regionSheetRecordCurrent(
                      formatCombo(chord,
                          keyLabels: KeyboardLabels.of(context))),
                },
                focusRingRadius: 6,
                inset: 1,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    // The same control the list shows for an unset row, rather
                    // than plain grey text. This sheet had the list's original
                    // defect — a status where a button belongs — on a field
                    // that is *only* ever clicked.
                    child: _chord == null
                        ? SetShortcutPill(
                            label: context.l10n.regionSheetClickToRecord)
                        : KeycapRow(chord: _chord),
                  ),
                ),
              ),
      ),
    ],
  );

  /// Says, *before* the combo is committed, what taking it will cost — and
  /// offers to pay it.
  ///
  /// Warning at the moment of choice is the difference between "pick another
  /// one" and "why is Left half suddenly unset". Offering the take in the same
  /// breath is the difference between that and "then go and find Left half".
  Widget _conflictNotice(PlatformTokens t) => Padding(
    padding: const EdgeInsets.only(left: 62, top: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.warning_amber_rounded, size: 13, color: t.warning),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _takeAnyway
                ? context.l10n.regionSheetConflictTaking(_conflict ?? '')
                : context.l10n.regionSheetConflict(_conflict ?? ''),
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: t.labelSecondary,
            ),
          ),
        ),
        if (!_takeAnyway) ...[
          const SizedBox(width: 8),
          MacControl(
            key: const ValueKey('region-take-anyway'),
            onPressed: () => setState(() => _takeAnyway = true),
            semanticLabel: context.l10n.regionSheetUseHereLabel,
            focusRingRadius: 5,
            inset: 2,
            child: Text(
              context.l10n.regionSheetUseHere,
              style: TextStyle(fontSize: 11, color: t.link),
            ),
          ),
        ],
      ],
    ),
  );

  /// Why a key pressed while recording was not used, under the field it was
  /// pressed in, while the field goes on listening.
  Widget _refusalNotice(PlatformTokens t, String why) => Padding(
    padding: const EdgeInsets.only(left: 62, top: 7),
    child: Text(
      why,
      style: TextStyle(fontSize: 11, height: 1.35, color: t.labelSecondary),
    ),
  );

  Widget _buttons(PlatformTokens t) => Row(
    children: [
      if (widget.onDelete != null)
        MacControl(
          key: const ValueKey('region-delete'),
          onPressed: widget.onDelete,
          semanticLabel: context.l10n.regionSheetDeleteLabel,
          focusRingRadius: 6,
          child: Text(
            // 'Delete' alone on screen, 'Delete region' to a reader: three
            // controls plus the sheet's padding do not fit the longer label,
            // and the row it sits in is the one place a wrap would look
            // broken rather than merely tight.
            context.l10n.regionSheetDelete,
            style: TextStyle(fontSize: 12.5, color: t.warning),
          ),
        ),
      const Spacer(),
      MacControl(
        key: const ValueKey('region-cancel'),
        onPressed: widget.onCancel,
        semanticLabel: context.l10n.regionSheetCancel,
        focusRingRadius: 6,
        child: Text(
          context.l10n.regionSheetCancel,
          style: TextStyle(fontSize: 12.5, color: t.labelPrimary),
        ),
      ),
      const SizedBox(width: 14),
      MacControl(
        key: const ValueKey('region-submit'),
        // Null, not a greyed-looking live button: a null onPressed is what
        // makes MacControl report isEnabled false, so a screen reader is
        // told the same thing the colour says.
        onPressed: _canSubmit ? _submit : null,
        semanticLabel: _creating
            ? context.l10n.regionSheetAddLabel
            : context.l10n.regionSheetSaveLabel,
        focusRingRadius: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
          decoration: BoxDecoration(
            color: _canSubmit ? t.accent : t.separator,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _creating
                ? context.l10n.regionSheetAdd
                : context.l10n.regionSheetSave,
            style: TextStyle(
              fontSize: 12.5,
              color: _canSubmit ? t.onAccent : t.labelTertiary,
            ),
          ),
        ),
      ),
    ],
  );
}

/// A short opaque id.
///
/// Opaque on purpose: it is written to preferences and must survive a rename
/// and a reshape, so it can never be derived from the name or the geometry.
String _newId() =>
    'r${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// The grid, with the current block filled. Modelled on `GridPreviewPainter` —
/// same cell treatment, so the sheet reads as the same family as the General
/// pane's miniature.
class _PickerGridPainter extends CustomPainter {
  _PickerGridPainter({
    required this.cols,
    required this.rows,
    required this.block,
    required this.cell,
    required this.fill,
  });

  final int cols;
  final int rows;
  final CellBlock? block;
  final Color cell;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / cols;
    final cellH = size.height / rows;
    if (cellW <= 0 || cellH <= 0) return;

    final base = Paint()..color = cell.withValues(alpha: 0.22);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = cell.withValues(alpha: 0.55);
    final selected = Paint()..color = fill;

    for (var c = 0; c < cols; c++) {
      for (var r = 0; r < rows; r++) {
        final inBlock =
            block != null &&
            c >= block!.c0 &&
            c <= block!.c1 &&
            r >= block!.r0 &&
            r <= block!.r1;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH).deflate(0.75),
          const Radius.circular(2),
        );
        canvas.drawRRect(rect, inBlock ? selected : base);
        canvas.drawRRect(rect, edge);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PickerGridPainter old) =>
      old.cols != cols ||
      old.rows != rows ||
      old.block != block ||
      old.cell != cell ||
      old.fill != fill;
}
