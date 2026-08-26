#!/usr/bin/env python3
"""Vygeneruje launcher ikony palubovky ve všech velikostech, které Edge chtějí.

Každá řada Edge má jinou velikost ikony (Edge 830 chce 35 px, Edge 1050 68 px).
Když se dodá jen jedna, překladač ji přeškáluje a nadává; proto se pro každou
velikost vyrobí vlastní PNG do `resources-icon<velikost>/drawables/`, které si
`monkey.jungle` přiřadí ke správným zařízením.

    python3 garmin/tools/make_ride_icon.py            # všechny velikosti
    python3 garmin/tools/make_ride_icon.py --size 68  # jen jednu

Ikona opakuje motiv palubovky: tříčtvrteční budík kadence s ručičkou.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib

from PIL import Image, ImageDraw

PROJECT_DIR = pathlib.Path(__file__).resolve().parents[1] / "RideDashboard"
LAYOUT_PATH = PROJECT_DIR / "resources" / "json" / "layout.json"

#: Velikosti ikon vyžadované jednotlivými Edge (compiler.json -> launcherIcon).
SIZES = (35, 36, 40, 56, 68)

SUPERSAMPLE = 8

#: Kam až vede vyplněná část budíku - jako by kolo jelo tempem.
FILL_RATIO = 0.62


def load_colors() -> dict:
    return json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))["colors"]


def rgb(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def render(size: int, colors: dict) -> Image.Image:
    side = size * SUPERSAMPLE
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    pen = side * 0.15
    inset = pen / 2 + side * 0.04
    box = (inset, inset, side - inset, side - inset)

    # Tříčtvrteční budík: od 135° po směru hodinových ručiček do 45°.
    start, span = 135.0, 270.0
    draw.arc(box, start=start, end=start + span, fill=rgb(colors["panelEdge"]), width=round(pen))
    draw.arc(box, start=start, end=start + span * FILL_RATIO, fill=rgb(colors["accent"]),
             width=round(pen))

    center = side / 2.0
    radius = center - inset
    cap = pen / 2.0
    for angle, color in ((start, "accent"), (start + span * FILL_RATIO, "accent")):
        radians = math.radians(angle)
        cx = center + radius * math.cos(radians)
        cy = center + radius * math.sin(radians)
        draw.ellipse((cx - cap, cy - cap, cx + cap, cy + cap), fill=rgb(colors[color]))

    # Ručička ukazuje na konec vyplněné části.
    needle = math.radians(start + span * FILL_RATIO)
    length = radius - pen * 0.9
    draw.line(
        (center, center, center + length * math.cos(needle), center + length * math.sin(needle)),
        fill=rgb(colors["text"]),
        width=round(side * 0.08),
    )
    hub = side * 0.09
    draw.ellipse((center - hub, center - hub, center + hub, center + hub), fill=rgb(colors["text"]))

    return image.resize((size, size), Image.LANCZOS)


def write(size: int, colors: dict) -> pathlib.Path:
    out = PROJECT_DIR / f"resources-icon{size}" / "drawables" / "launcher_icon.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    render(size, colors).save(out)

    # Každá složka potřebuje i svůj drawables.xml, jinak si jí překladač nevšimne.
    (out.parent / "drawables.xml").write_text(
        '<drawables>\n    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>\n</drawables>\n',
        encoding="utf-8",
    )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--size", type=int, action="append", help="jen tahle velikost (px)")
    args = parser.parse_args()

    colors = load_colors()
    for size in args.size or SIZES:
        print(write(size, colors))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
