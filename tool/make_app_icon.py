#!/usr/bin/env python3
"""Generate macOS/Windows app icons from Orthant's own visual language.

Run:  python3 tool/make_app_icon.py

The art is generated rather than drawn by hand so it stays reproducible and
tweakable — change a constant here, re-run, and every size regenerates
consistently. The output *is* committed, because a build must not depend on
having Pillow installed.

Design: the same motif the app already uses in two places — the menu-bar
template icon (a 2x2 of equal squares) and `RegionGlyph` (a screen with one
region filled). Three cells sit back at partial opacity and one reads as
"placed", which is what the app does, rather than a literal grid.
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"

# The same icon, as a Flutter asset, for the About pane to draw.
#
# Emitted by this script rather than copied by hand: a second PNG maintained
# separately is a second PNG that silently goes stale the first time the
# constants above change, and the whole point of this file is that the icon has
# one source. 256 px is generous for a 64 pt view even at 2x, and costs ~10 KB.
FLUTTER_ASSET = ROOT / "assets/app_icon.png"
FLUTTER_ASSET_SIZE = 256

# Rendered large and downsampled — Pillow has no analytic antialiasing, so
# supersampling is what keeps the 16 pt corners clean.
CANVAS = 4096

# macOS Big Sur+ icons do not fill their canvas: the rounded square occupies
# ~80% of it, with the rest transparent padding the system relies on for its
# own shadowing and alignment.
PLATE_FRACTION = 0.805
CORNER_FRACTION = 0.2237  # of the plate's edge — matches Apple's squircle-ish r

ACCENT_TOP = (10, 132, 255)  # systemBlue, dark-appearance variant
ACCENT_BOTTOM = (0, 96, 214)

GRID_FRACTION = 0.52  # of the plate — the motif's bounding box
GUTTER_FRACTION = 0.085  # of the grid, between cells
CELL_RADIUS_FRACTION = 0.16  # of a cell's edge


def rounded(size: int, radius: int, fill) -> Image.Image:
    """A rounded rectangle on its own transparent layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=radius, fill=fill
    )
    return layer


def build() -> Image.Image:
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    plate_size = int(CANVAS * PLATE_FRACTION)
    plate_xy = (CANVAS - plate_size) // 2

    # Vertical gradient, then masked by the rounded plate. Flat colour reads as
    # a placeholder at 1024; the gradient is most of what makes it look drawn.
    gradient = Image.new("RGBA", (1, plate_size))
    for y in range(plate_size):
        t = y / max(plate_size - 1, 1)
        gradient.putpixel(
            (0, y),
            tuple(
                round(a + (b - a) * t)
                for a, b in zip(ACCENT_TOP, ACCENT_BOTTOM)
            )
            + (255,),
        )
    gradient = gradient.resize((plate_size, plate_size))
    plate_mask = rounded(
        plate_size, int(plate_size * CORNER_FRACTION), (255, 255, 255, 255)
    )
    icon.paste(gradient, (plate_xy, plate_xy), plate_mask)

    # The 2x2 motif.
    grid = int(plate_size * GRID_FRACTION)
    gutter = int(grid * GUTTER_FRACTION)
    cell = (grid - gutter) // 2
    radius = int(cell * CELL_RADIUS_FRACTION)
    origin = (CANVAS - grid) // 2

    # One cell is "placed": solid, while the others sit back. That contrast is
    # the whole idea — a grid alone says "grid", a grid with one cell filled
    # says "put this window there", which is the app. Bottom-right keeps the
    # weight low and off the corner the system rounds hardest.
    placed = (1, 1)
    for col in range(2):
        for row in range(2):
            is_placed = (col, row) == placed
            alpha = 255 if is_placed else 110
            layer = rounded(cell, radius, (255, 255, 255, alpha))
            icon.alpha_composite(
                layer,
                (origin + col * (cell + gutter), origin + row * (cell + gutter)),
            )

    return icon


def main() -> None:
    icon = build()
    for size in (16, 32, 64, 128, 256, 512, 1024):
        icon.resize((size, size), Image.LANCZOS).save(OUT / f"app_icon_{size}.png")
        print(f"wrote app_icon_{size}.png")

    icon.resize((FLUTTER_ASSET_SIZE,) * 2, Image.LANCZOS).save(FLUTTER_ASSET)
    print(f"wrote {FLUTTER_ASSET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
