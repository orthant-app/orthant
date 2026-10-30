import 'package:flutter/material.dart';

import 'mac_control.dart';
import 'platform_theme.dart';

/// A macOS pop-up button: a rounded button showing the current choice and a
/// pair of chevrons, which opens a menu of every choice with the current one
/// ticked. `NSPopUpButton`, which is what a preferences pane uses to pick one
/// of a handful of named things.
///
/// [MenuAnchor] for the menu, so the platform-independent parts (placement
/// against the window's edge, dismissal by an outside click or Esc, arrow-key
/// traversal, the screen reader's menu semantics) are Flutter's. [MacControl]
/// for the button, so a click, Space and Return all reach one callback and the
/// focus ring matches the other controls in the pane.
///
/// Picking the entry that is already selected reports nothing: [onChanged] says
/// the choice *changed*. A caller whose stored value is finer than its entries
/// (the Language picker shows a Hong Kong choice as Traditional Chinese) relies
/// on that, because re-picking the entry it shows must not rewrite the value
/// into the entry's own.
class MacPopUpButton<T> extends StatelessWidget {
  const MacPopUpButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.tokens,
    this.semanticLabel,
    this.localeOf,
  });

  /// The entry that is selected, matched to [items] by `==`. A value no entry
  /// has shows an empty button, and no entry ticked.
  final T value;

  /// Every entry, top to bottom, as its value and the words it shows. The value
  /// may be null (`MacPopUpButton<String?>`): "no choice" is a choice here.
  final List<(T, String)> items;

  /// Null disables the button: it stops taking focus and announces itself as
  /// disabled, as [MacControl] does for any control.
  final ValueChanged<T>? onChanged;

  final PlatformTokens tokens;

  /// What a screen reader calls the button, already in the app's language;
  /// the selected entry is read as its value after it. Without one the button
  /// is named by the selected entry alone, which is right where the visible
  /// label next to it is the name.
  final String? semanticLabel;

  /// The locale an entry's words are drawn in, by the entry's value; null (the
  /// function or its answer) keeps the app's. A language named in its own
  /// script needs it: Han characters share code points across Chinese, Japanese
  /// and Korean, so under an English UI the font may draw 简体中文 and 繁體中文
  /// with the wrong glyph forms. It also tells a screen reader which language
  /// to speak each entry in.
  final Locale? Function(T value)? localeOf;

  @override
  Widget build(BuildContext context) => _PopUp<T>(this);
}

/// Wide enough for a language's name or two, narrow enough to leave the note
/// under it room on the 560 pt window. The menu is at least this wide too.
const double _kWidth = 150;

class _PopUp<T> extends StatefulWidget {
  const _PopUp(this.button);

  final MacPopUpButton<T> button;

  @override
  State<_PopUp<T>> createState() => _PopUpState<T>();
}

class _PopUpState<T> extends State<_PopUp<T>> {
  /// Held by the entry the menu opens on, so opening can put the keyboard
  /// there. A [MenuAnchor] leaves focus on the button, where the arrow keys
  /// do nothing.
  final FocusNode _opensOn = FocusNode(debugLabel: 'MacPopUpButton entry');

  MacPopUpButton<T> get _b => widget.button;

  /// Where the menu opens: on the selected entry, as an `NSPopUpButton`
  /// does, or on the first when none is.
  int get _selected => _b.items.indexWhere((i) => i.$1 == _b.value);

  @override
  void dispose() {
    _opensOn.dispose();
    super.dispose();
  }

  void _focusEntry() {
    // The entries are built in the frame that opening schedules.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _opensOn.context != null) _opensOn.requestFocus();
    });
  }

  void _pick(T value) {
    if (value == _b.value) return;
    _b.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = _b.tokens;
    final selected = _selected;
    final opensOn = selected < 0 ? 0 : selected;
    final shown = selected < 0 ? '' : _b.items[selected].$2;
    final live = _b.onChanged != null;

    return MenuAnchor(
      onOpen: _focusEntry,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.contentBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Color(0x40000000)),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        minimumSize: const WidgetStatePropertyAll(Size(_kWidth, 0)),
        // Standard, not the desktop default: a compact density takes 8 pt off
        // every minimum size, which left the menu narrower than its button.
        visualDensity: VisualDensity.standard,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: t.keycapBorder),
          ),
        ),
      ),
      menuChildren: [
        for (var i = 0; i < _b.items.length; i++)
          MenuItemButton(
            focusNode: i == opensOn ? _opensOn : null,
            style: _entryStyle(t),
            leadingIcon: SizedBox(
              width: 14,
              child: i == selected ? const Icon(Icons.check, size: 13) : null,
            ),
            onPressed: () => _pick(_b.items[i].$1),
            child: Semantics(
              selected: i == selected,
              child: Text(
                _b.items[i].$2,
                locale: _b.localeOf?.call(_b.items[i].$1),
              ),
            ),
          ),
      ],
      builder: (context, controller, _) {
        final face = Row(
          children: [
            Expanded(
              child: Text(
                shown,
                locale: selected < 0
                    ? null
                    : _b.localeOf?.call(_b.items[selected].$1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: t.labelPrimary),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.unfold_more, size: 14, color: t.labelSecondary),
          ],
        );
        return Opacity(
          opacity: live ? 1 : 0.42,
          child: MacControl(
            onPressed: live
                ? () => controller.isOpen ? controller.close() : controller.open()
                : null,
            focusRingRadius: 6,
            child: Container(
              width: _kWidth,
              padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
              decoration: BoxDecoration(
                color: t.contentBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: t.keycapBorder),
                boxShadow: [
                  BoxShadow(
                    color: t.keycapShadow,
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              // A name for the button and the choice as its value; the row
              // below it is then only a picture of those.
              child: _b.semanticLabel == null
                  ? face
                  : Semantics(
                      label: _b.semanticLabel,
                      value: shown,
                      excludeSemantics: true,
                      child: face,
                    ),
            ),
          ),
        );
      },
    );
  }

  /// A menu entry the way macOS draws one: the accent behind white text for
  /// whichever the pointer or the keyboard is on, nothing otherwise.
  ButtonStyle _entryStyle(PlatformTokens t) {
    bool on(Set<WidgetState> s) =>
        s.contains(WidgetState.focused) || s.contains(WidgetState.hovered);
    Color text(Set<WidgetState> s) => on(s) ? t.onAccent : t.labelPrimary;
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(text),
      iconColor: WidgetStateProperty.resolveWith(text),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => on(s) ? t.accent : Colors.transparent,
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12.5)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6),
      ),
      // As wide as the menu's inside (its 4 pt padding either side) and as
      // tall as a macOS menu row, with none of Material's touch padding.
      minimumSize: const WidgetStatePropertyAll(Size(_kWidth - 8, 24)),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
