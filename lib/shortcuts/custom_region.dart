/// Bounds on a region's *denominator*.
///
/// Deliberately not `kMinGridAxis` (which is 2). That constant governs the
/// overlay grid, where a single row or column would defeat the point of a thing
/// you aim at. A region's denominator is arithmetic: `cols: 3, rows: 1` — left
/// two-thirds, full height — is a perfectly good region. Do not "fix" these to
/// match.
const int kMinRegionAxis = 1;
const int kMaxRegionAxis = 12;

/// A user-defined placement: a block of cells on a grid of its own choosing.
///
/// **Self-describing on purpose.** Storing only `c0..c1` against the user's live
/// grid setting would mean changing that setting silently reinterprets every
/// saved shortcut — "left ⅔" drawn on a 6-column grid would become fullscreen on
/// a 4-column one, and nothing on screen would say why. Carrying [cols] and
/// [rows] makes a region mean the same thing forever.
class CustomRegion {
  /// Stable identity. Never the name — renaming must be free, and two regions
  /// may legitimately share one.
  final String id;
  final String name;
  final int cols;
  final int rows;
  final int c0;
  final int c1;
  final int r0;
  final int r1;

  const CustomRegion({
    required this.id,
    required this.name,
    required this.cols,
    required this.rows,
    required this.c0,
    required this.c1,
    required this.r0,
    required this.r1,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cols': cols,
        'rows': rows,
        'c0': c0,
        'c1': c1,
        'r0': r0,
        'r1': r1,
      };

  /// One persisted region, or null if it isn't one we can trust.
  ///
  /// Tolerant for the same reason `Binding.tryFromJson` is: this reads a file we
  /// did not necessarily write — an older release's, a newer one's, or a corrupt
  /// one — on the launch path, before any shortcut is registered. A rejected
  /// region costs the user that one row; a thrown one costs every shortcut, with
  /// no way back short of deleting the preferences by hand.
  static CustomRegion? tryFromJson(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id'];
    final name = entry['name'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;

    final cols = entry['cols'];
    final rows = entry['rows'];
    final c0 = entry['c0'];
    final c1 = entry['c1'];
    final r0 = entry['r0'];
    final r1 = entry['r1'];
    if (cols is! int || rows is! int) return null;
    if (c0 is! int || c1 is! int || r0 is! int || r1 is! int) return null;
    if (!_axisOk(cols) || !_axisOk(rows)) return null;
    if (!_blockOk(c0, c1, cols) || !_blockOk(r0, r1, rows)) return null;

    return CustomRegion(
      id: id,
      name: name,
      cols: cols,
      rows: rows,
      c0: c0,
      c1: c1,
      r0: r0,
      r1: r1,
    );
  }

  static bool _axisOk(int n) => n >= kMinRegionAxis && n <= kMaxRegionAxis;

  /// A block must lie inside its own grid. `hi < extent`, not `<=`: the indices
  /// are inclusive at both ends, so `c1 == cols` is one column off the edge and
  /// `gridBlock` would place a window past the display.
  static bool _blockOk(int lo, int hi, int extent) =>
      lo >= 0 && lo <= hi && hi < extent;

  CustomRegion copyWith({
    String? name,
    int? cols,
    int? rows,
    int? c0,
    int? c1,
    int? r0,
    int? r1,
  }) =>
      CustomRegion(
        id: id,
        name: name ?? this.name,
        cols: cols ?? this.cols,
        rows: rows ?? this.rows,
        c0: c0 ?? this.c0,
        c1: c1 ?? this.c1,
        r0: r0 ?? this.r0,
        r1: r1 ?? this.r1,
      );

  /// A copy under a new [id]. Separate from [copyWith] because changing the id
  /// is not an edit — it makes a *different* region, which is why the id is not
  /// among the fields [copyWith] will touch.
  CustomRegion copyWithId(String id) => CustomRegion(
        id: id,
        name: name,
        cols: cols,
        rows: rows,
        c0: c0,
        c1: c1,
        r0: r0,
        r1: r1,
      );

  @override
  bool operator ==(Object other) =>
      other is CustomRegion &&
      other.id == id &&
      other.name == name &&
      other.cols == cols &&
      other.rows == rows &&
      other.c0 == c0 &&
      other.c1 == c1 &&
      other.r0 == r0 &&
      other.r1 == r1;

  @override
  int get hashCode => Object.hash(id, name, cols, rows, c0, c1, r0, r1);

  @override
  String toString() =>
      'CustomRegion($id "$name" ${cols}x$rows $c0..$c1, $r0..$r1)';
}

/// A default name for the shape just drawn.
///
/// A convenience the user overwrites, never an identity — [CustomRegion.id] is
/// that, which is what makes renaming free. Deliberately shallow: it names the
/// six shapes that have an obvious word ("Left ⅔", "Top ½") and gives up on the
/// rest rather than inventing something like "columns 2–4 of 6". A wrong-sounding
/// name is one text field away from right; a long wrong one is just noise.
String suggestRegionName({
  required int cols,
  required int rows,
  required int c0,
  required int c1,
  required int r0,
  required int r1,
}) {
  final fullWidth = c0 == 0 && c1 == cols - 1;
  final fullHeight = r0 == 0 && r1 == rows - 1;

  if (fullWidth && fullHeight) return 'Full screen';
  if (fullHeight && c0 == 0) return 'Left ${_fraction(c1 + 1, cols)}';
  if (fullHeight && c1 == cols - 1) return 'Right ${_fraction(cols - c0, cols)}';
  if (fullWidth && r0 == 0) return 'Top ${_fraction(r1 + 1, rows)}';
  if (fullWidth && r1 == rows - 1) return 'Bottom ${_fraction(rows - r0, rows)}';
  return 'Custom region';
}

/// [n]/[d] reduced, as a vulgar-fraction glyph where one exists.
///
/// Reduced first so that the same *shape* gets the same name whatever grid it
/// was drawn on: 8/12 and 4/6 are both ⅔, and a user who changes the picker's
/// denominators should not see the suggestion change under them.
String _fraction(int n, int d) {
  final g = _gcd(n, d);
  return _glyphs['${n ~/ g}/${d ~/ g}'] ?? '${n ~/ g}/${d ~/ g}';
}

/// The fractions Unicode has a single glyph for. Anything else falls back to
/// `n/d`, which is honest and readable — "Left 3/7" beats "Left ⅗-ish".
const Map<String, String> _glyphs = {
  '1/2': '½',
  '1/3': '⅓', '2/3': '⅔',
  '1/4': '¼', '3/4': '¾',
  '1/5': '⅕', '2/5': '⅖', '3/5': '⅗', '4/5': '⅘',
  '1/6': '⅙', '5/6': '⅚',
  '1/8': '⅛', '3/8': '⅜', '5/8': '⅝', '7/8': '⅞',
};

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

/// [region] re-expressed on a finer grid, so it can be *reshaped* rather than
/// only nudged — without moving the rectangle it already describes.
///
/// A region is edited on its own denominators, because reinterpreting it on the
/// live grid would change its shape under the user. But that leaves a coarse one
/// stuck: a `3 × 1` "Left ⅔" has a single row, so it cannot become a top, a
/// bottom or a corner without being deleted and drawn again.
///
/// The way out needs no control. Each axis moves to the smallest **multiple** of
/// its stored denominator that is at least the live grid's and still within
/// [kMaxRegionAxis]; the selection scales by the same factor. A multiple is what
/// makes this exact rather than approximate — columns 0–1 of 3 *are* columns 0–3
/// of 6 — so refining can never move a window, which is the property its tests
/// assert directly.
///
/// Where no multiple fits, the axis is left alone: a coarse grid beats a moved
/// window.
///
/// The guarantee holds **at any gap**, but only because `gapForPlacement`
/// measures the block rather than the denominators. An earlier grid-wide clamp
/// let twelfths shrink a gap that thirds kept, so refining a `3 × 1` and then
/// dragging one axis moved the other — the same fractions, a different gap, a
/// different window.
CustomRegion refineForEditing(
  CustomRegion region, {
  required int gridCols,
  required int gridRows,
}) {
  final cols = _finerAxis(region.cols, gridCols);
  final rows = _finerAxis(region.rows, gridRows);
  final fc = cols ~/ region.cols;
  final fr = rows ~/ region.rows;
  return region.copyWith(
    cols: cols,
    rows: rows,
    c0: region.c0 * fc,
    c1: (region.c1 + 1) * fc - 1,
    r0: region.r0 * fr,
    r1: (region.r1 + 1) * fr - 1,
  );
}

/// The smallest multiple of [stored] that is at least [wanted] and no more than
/// [kMaxRegionAxis] — or [stored] itself when there is none.
int _finerAxis(int stored, int wanted) {
  if (stored >= wanted) return stored;
  final multiple = ((wanted + stored - 1) ~/ stored) * stored;
  return multiple <= kMaxRegionAxis ? multiple : stored;
}
