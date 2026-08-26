#!/usr/bin/env python3
"""Vyřízne z okna simulátoru samotnou obrazovku přístroje.

Snímek ze `sim_shot.sh` je celé okno i s rámečkem přístroje a lištou menu.
Do dokumentace patří jen displej a ten se najde podle proužku baterie: vede
přes celou šířku displeje těsně nad jeho spodní hranou a má barvu `colors.ok`,
kterou jinde na snímku nic nemá. Zbytek dopočítá rozlišení z device packu.

    python3 garmin/tools/crop_screen.py edge830 /tmp/sim-sweep/edge830.png \\
        garmin/docs/device/edge830.png
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from PIL import Image

GARMIN_DIR = pathlib.Path(__file__).resolve().parents[1]
DEVICES_DIR = pathlib.Path.home() / ".Garmin" / "ConnectIQ" / "Devices"

#: Zařízení, která si v monkey.jungle berou kompaktní rozvržení.
COMPACT = {"edge830", "edge530", "edge840", "edge540", "edgemtb", "edgeexplore2"}


def layout_of(device: str) -> dict:
    folder = "resources-compact" if device in COMPACT else "resources"
    return json.loads((GARMIN_DIR / "RideDashboard" / folder / "json" / "layout.json")
                      .read_text(encoding="utf-8"))


def rgb(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def resolution(device: str) -> tuple[int, int]:
    compiler = json.loads((DEVICES_DIR / device / "compiler.json").read_text(encoding="utf-8"))
    size = compiler["resolution"]
    return size["width"], size["height"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("device")
    parser.add_argument("source")
    parser.add_argument("target")
    args = parser.parse_args()

    image = Image.open(args.source).convert("RGB")
    pixels = image.load()
    width, height = resolution(args.device)
    layout = layout_of(args.device)
    strip_color = rgb(layout["colors"]["ok"])
    battery = layout["cockpit"]["battery"]
    canvas_height = layout["canvas"]["height"]

    # Displej přístroje má 16 bitů na pixel, takže barvy ze snímku nesedí na
    # zadané hodnoty přesně - zelená 61,220,151 dorazí jako 57,222,148.
    def close(pixel: tuple[int, int, int], wanted: tuple[int, int, int]) -> bool:
        return all(abs(pixel[i] - wanted[i]) <= 8 for i in range(3))

    left, strip_bottom = image.width, -1
    for y in range(image.height):
        for x in range(image.width):
            if close(pixels[x, y], strip_color):
                left = min(left, x)
                strip_bottom = max(strip_bottom, y)

    if strip_bottom < 0:
        print("proužek baterie se na snímku nenašel", file=sys.stderr)
        return 1

    # Pod proužkem zbývá k dolní hraně displeje ještě kousek plátna.
    scale = height / float(canvas_height)
    bottom = strip_bottom + round((canvas_height - battery["y"] - battery["height"]) * scale)

    out = pathlib.Path(args.target)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.crop((left, bottom - height + 1, left + width, bottom + 1)).save(out)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
