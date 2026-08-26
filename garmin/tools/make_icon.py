#!/usr/bin/env python3
"""Vygeneruje launcher ikonu z barev v theme.json (miniatura prstence |psi|^2)."""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

from preview import PROJECT_DIR, load_theme, rgb

OUT = PROJECT_DIR / "resources" / "drawables" / "launcher_icon.png"
SIZE = 40
SUPERSAMPLE = 8
SEGMENTS = [("ham", 0.10), ("spam", 0.14), ("phishing", 0.76)]


def main() -> int:
    theme = load_theme()
    colors = theme["colors"]
    side = SIZE * SUPERSAMPLE
    image = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    pen = round(side * 0.16)
    inset = pen // 2 + 1
    box = (inset, inset, side - inset - 1, side - inset - 1)

    gap = 6.0
    available = 360.0 - gap * len(SEGMENTS)
    cursor = 90.0
    for name, share in SEGMENTS:
        sweep = share * available
        draw.arc(box, start=-cursor, end=-cursor + sweep, fill=rgb(colors[name]), width=pen)
        cursor -= sweep + gap

    dot = round(side * 0.13)
    draw.ellipse(
        (side // 2 - dot, side // 2 - dot, side // 2 + dot, side // 2 + dot),
        fill=rgb(colors["text"]),
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    image.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print(OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
