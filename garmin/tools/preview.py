#!/usr/bin/env python3
"""Náhled dashboardu bez simulátoru.

Connect IQ simulátor umí spustit jen aplikaci přeloženou pro konkrétní
zařízení a device packy jdou stáhnout výhradně po přihlášení k Garmin
developer účtu. Tenhle skript proto vykreslí tutéž obrazovku do PNG:
čte stejné `resources/json/theme.json` jako hodinková aplikace a opakuje
kreslicí postup z `source/DashboardView.mc` (prstenec |psi|^2, kolaps ve
středu, proužek neurčitosti, patička).

Je to náhled, ne snímek ze simulátoru - písma jsou nahrazená DejaVu, takže
metriky textu se od Garmin fontů liší o pár pixelů.

    python3 garmin/tools/preview.py --all --out-dir garmin/docs/preview
    python3 garmin/tools/preview.py --device fenix847mm --scenario phishing
    python3 garmin/tools/preview.py --device venu3 --json data.json
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import urllib.request

from PIL import Image, ImageDraw, ImageFont

PROJECT_DIR = pathlib.Path(__file__).resolve().parents[1] / "QMailDashboard"
THEME_PATH = PROJECT_DIR / "resources" / "json" / "theme.json"

#: Vykreslujeme ve větším rozlišení a pak zmenšíme - Pillow neumí antialiasing
#: oblouků, tohle je nejlacinější způsob, jak dostat hladké hrany.
SUPERSAMPLE = 4

#: Poměr velikosti písma k úhlopříčce displeje. Přibližná náhrada za Garmin
#: fonty, které jsou pro každé zařízení jiné.
FONT_SCALE = {
    "xtiny": 0.052,
    "tiny": 0.062,
    "small": 0.072,
    "medium": 0.082,
    "large": 0.098,
    "number_medium": 0.155,
}

FONT_CANDIDATES = {
    "regular": [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/System/Library/Fonts/Supplemental/DejaVuSans.ttf",
    ],
    "bold": [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/System/Library/Fonts/Supplemental/DejaVuSans-Bold.ttf",
    ],
}

DEVICES = {
    "fenix847mm": {"label": "fenix 8 – 47 mm", "size": (454, 454), "shape": "round"},
    "fenix843mm": {"label": "fenix 8 – 43 mm", "size": (416, 416), "shape": "round"},
    "venu3": {"label": "Venu 3", "size": (454, 454), "shape": "round"},
    "fr965": {"label": "Forerunner 965", "size": (454, 454), "shape": "round"},
    "fr265": {"label": "Forerunner 265", "size": (416, 416), "shape": "round"},
    "vivoactive5": {"label": "vívoactive 5", "size": (390, 390), "shape": "round"},
    "fenix7": {"label": "fenix 7 (MIP)", "size": (260, 260), "shape": "round"},
    "venusq2": {"label": "Venu Sq 2", "size": (320, 360), "shape": "rectangle"},
}

#: Stavy schránky pro ukázku. `phishing` odpovídá rozboru
#: examples/phishing.eml, jak ho má v README hlavní projekt.
SCENARIOS = {
    "phishing": {
        "probabilities": {"ham": 0.011, "spam": 0.027, "phishing": 0.963},
        "uncertainty": 0.165,
        "needs_review": 3,
        "scanned": 128,
    },
    "spam": {
        "probabilities": {"ham": 0.104, "spam": 0.781, "phishing": 0.115},
        "uncertainty": 0.472,
        "needs_review": 1,
        "scanned": 128,
    },
    "clean": {
        "probabilities": {"ham": 0.947, "spam": 0.038, "phishing": 0.015},
        "uncertainty": 0.121,
        "needs_review": 0,
        "scanned": 128,
    },
    "uncertain": {
        "probabilities": {"ham": 0.381, "spam": 0.286, "phishing": 0.333},
        "uncertainty": 0.981,
        "needs_review": 7,
        "scanned": 128,
    },
}

VERDICT_ORDER = ["ham", "spam", "phishing"]
VERDICT_LABELS = {"ham": "LEGIT", "spam": "SPAM", "phishing": "PHISH"}


def load_theme() -> dict:
    return json.loads(THEME_PATH.read_text(encoding="utf-8"))


def rgb(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def load_font(weight: str, pixels: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES[weight]:
        if pathlib.Path(path).exists():
            return ImageFont.truetype(path, pixels)
    return ImageFont.load_default()


def normalized(data: dict) -> tuple[list[float], str]:
    values = [float(data["probabilities"].get(name, 0.0)) for name in VERDICT_ORDER]
    total = sum(values)
    if total <= 0:
        values = [1.0, 0.0, 0.0]
        total = 1.0
    values = [value / total for value in values]
    peak = VERDICT_ORDER[values.index(max(values))]
    return values, peak


def draw_centered(draw: ImageDraw.ImageDraw, xy, text, font, fill) -> None:
    draw.text(xy, text, font=font, fill=fill, anchor="mm")


def render(device: str, data: dict, theme: dict) -> Image.Image:
    spec = DEVICES[device]
    width, height = spec["size"]
    scale = SUPERSAMPLE
    canvas = Image.new("RGB", (width * scale, height * scale), rgb(theme["colors"]["background"]))
    draw = ImageDraw.Draw(canvas)

    size = min(width, height) * scale
    cx, cy = width * scale / 2, height * scale / 2
    colors = theme["colors"]
    ring = theme["ring"]
    layout = theme["layout"]

    probabilities, peak = normalized(data)

    # --- prstenec: obvod displeje je celý pravděpodobnostní prostor ---------
    radius = size * ring["radiusPct"]
    pen = max(1, round(size * ring["widthPct"]))
    box = (cx - radius, cy - radius, cx + radius, cy + radius)
    draw.ellipse(box, outline=rgb(colors["track"]), width=pen)

    gap = float(ring["gapDeg"])
    available = 360.0 - gap * len(probabilities)
    cursor = float(ring["startDeg"])
    for name, probability in zip(VERDICT_ORDER, probabilities):
        sweep = probability * available
        if sweep > 0.5:
            # Garmin měří úhly proti směru hodinových ručiček, Pillow po směru.
            draw.arc(box, start=-cursor, end=-cursor + sweep, fill=rgb(colors[name]), width=pen)
        cursor -= sweep + gap

    # --- texty --------------------------------------------------------------
    font_xtiny = load_font("regular", round(size * FONT_SCALE["xtiny"]))
    font_large = load_font("bold", round(size * FONT_SCALE["large"]))
    font_number = load_font("bold", round(size * FONT_SCALE["number_medium"]))

    title = "qmail · demo" if data.get("demo", True) else "qmail"
    draw_centered(draw, (cx, height * scale * layout["titlePct"]), title, font_xtiny, rgb(colors["textDim"]))

    draw_centered(
        draw,
        (cx, height * scale * layout["verdictPct"]),
        VERDICT_LABELS[peak],
        font_large,
        rgb(colors[peak]),
    )

    percent = math.floor(max(probabilities) * 100.0 + 0.5)
    draw_centered(
        draw,
        (cx, height * scale * layout["confidencePct"]),
        f"{percent}%",
        font_number,
        rgb(colors["text"]),
    )

    # --- neurčitost (entropie) ---------------------------------------------
    uncertainty = float(data.get("uncertainty", 0.0))
    draw_centered(
        draw,
        (cx, height * scale * layout["uncertaintyLabelPct"]),
        f"uncertainty {uncertainty:.2f}",
        font_xtiny,
        rgb(colors["textDim"]),
    )

    bar_width = size * layout["uncertaintyBarWidthPct"]
    bar_height = max(2 * scale, size * layout["uncertaintyBarHeightPct"])
    bar_x = (width * scale - bar_width) / 2
    bar_y = height * scale * layout["uncertaintyBarPct"]
    draw.rectangle((bar_x, bar_y, bar_x + bar_width, bar_y + bar_height), fill=rgb(colors["track"]))
    filled = bar_width * min(max(uncertainty, 0.0), 1.0)
    if filled > 0:
        draw.rectangle((bar_x, bar_y, bar_x + filled, bar_y + bar_height), fill=rgb(colors["accent"]))

    # --- patička ------------------------------------------------------------
    footer = f"{int(data.get('needs_review', 0))}/{int(data.get('scanned', 0))} review"
    draw_centered(draw, (cx, height * scale * layout["footerPct"]), footer, font_xtiny, rgb(colors["textDim"]))

    canvas = canvas.resize((width, height), Image.LANCZOS)
    return mask_to_shape(canvas, spec["shape"])


def render_glance(data: dict, theme: dict, width: int = 454, height: int = 84) -> Image.Image:
    """Náhled glance pohledu podle source/GlanceView.mc."""
    scale = SUPERSAMPLE
    colors = theme["colors"]
    canvas = Image.new("RGB", (width * scale, height * scale), rgb(colors["background"]))
    draw = ImageDraw.Draw(canvas)

    probabilities, peak = normalized(data)
    percent = math.floor(max(probabilities) * 100.0 + 0.5)
    font = load_font("bold", round(height * scale * 0.42))
    draw.text(
        (0, height * scale * 0.42),
        f"qmail · {VERDICT_LABELS[peak]} {percent}%",
        font=font,
        fill=rgb(colors["text"]),
        anchor="lm",
    )

    bar_y = height * scale - 6 * scale
    bar_height = 4 * scale
    draw.rectangle((0, bar_y, width * scale, bar_y + bar_height), fill=rgb(colors["track"]))
    cursor = 0.0
    for name, probability in zip(VERDICT_ORDER, probabilities):
        segment = width * scale * probability
        if segment >= 1:
            draw.rectangle((cursor, bar_y, cursor + segment, bar_y + bar_height), fill=rgb(colors[name]))
        cursor += segment

    return canvas.resize((width, height), Image.LANCZOS)


def mask_to_shape(image: Image.Image, shape: str) -> Image.Image:
    """Ořízne obraz na tvar displeje, aby náhled odpovídal skutečnému panelu."""
    width, height = image.size
    mask = Image.new("L", (width * 4, height * 4), 0)
    painter = ImageDraw.Draw(mask)
    if shape == "round":
        painter.ellipse((0, 0, width * 4 - 1, height * 4 - 1), fill=255)
    else:
        radius = min(width, height) * 4 * 0.12
        painter.rounded_rectangle((0, 0, width * 4 - 1, height * 4 - 1), radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask.resize((width, height), Image.LANCZOS))
    return out


def with_bezel(screen: Image.Image, label: str) -> Image.Image:
    """Vloží displej do jednoduchého pouzdra s popiskem zařízení."""
    width, height = screen.size
    pad = round(min(width, height) * 0.055)
    caption = round(min(width, height) * 0.13)
    canvas = Image.new("RGBA", (width + 2 * pad, height + 2 * pad + caption), (12, 12, 14, 255))
    draw = ImageDraw.Draw(canvas)

    case = (0, 0, width + 2 * pad - 1, height + 2 * pad - 1)
    if screen.size[0] == screen.size[1]:
        draw.ellipse(case, fill=(30, 30, 34), outline=(78, 78, 86), width=max(2, pad // 4))
    else:
        draw.rounded_rectangle(case, radius=pad * 2, fill=(30, 30, 34), outline=(78, 78, 86), width=max(2, pad // 4))

    canvas.alpha_composite(screen.convert("RGBA"), (pad, pad))

    font = load_font("regular", max(11, round(min(width, height) * 0.042)))
    draw.text(
        ((width + 2 * pad) / 2, height + 2 * pad + caption / 2 - pad / 2),
        label,
        font=font,
        fill=(150, 150, 158, 255),
        anchor="mm",
    )
    return canvas


def strip(images: list[Image.Image], gap: int = 28, background=(12, 12, 14)) -> Image.Image:
    total_width = sum(image.width for image in images) + gap * (len(images) + 1)
    height = max(image.height for image in images) + 2 * gap
    canvas = Image.new("RGBA", (total_width, height), background + (255,))
    x = gap
    for image in images:
        canvas.alpha_composite(image.convert("RGBA"), (x, (height - image.height) // 2))
        x += image.width + gap
    return canvas.convert("RGB")


def load_data(args) -> dict:
    if args.json:
        if args.json.startswith("http://") or args.json.startswith("https://"):
            with urllib.request.urlopen(args.json, timeout=10) as response:
                payload = json.loads(response.read().decode())
        else:
            payload = json.loads(pathlib.Path(args.json).read_text(encoding="utf-8"))
        payload.setdefault("demo", False)
        return payload
    data = dict(SCENARIOS[args.scenario])
    data["demo"] = True
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--device", choices=sorted(DEVICES), default="fenix847mm")
    parser.add_argument("--scenario", choices=sorted(SCENARIOS), default="phishing")
    parser.add_argument("--json", help="soubor nebo URL s daty z qmailu (formát qmail_server.py)")
    parser.add_argument("--out", help="cílový PNG soubor")
    parser.add_argument("--out-dir", default="garmin/docs/preview")
    parser.add_argument("--all", action="store_true", help="vykreslit všechna zařízení i všechny scénáře")
    parser.add_argument("--no-bezel", action="store_true", help="jen holý displej, bez pouzdra")
    args = parser.parse_args()

    theme = load_theme()
    out_dir = pathlib.Path(args.out_dir)

    if args.all:
        out_dir.mkdir(parents=True, exist_ok=True)

        scenario_images = []
        for name in ["clean", "spam", "phishing", "uncertain"]:
            data = dict(SCENARIOS[name], demo=True)
            screen = render("fenix847mm", data, theme)
            screen.save(out_dir / f"scenario-{name}.png")
            scenario_images.append(with_bezel(screen, name))
        strip(scenario_images).save(out_dir / "scenarios.png")

        device_images = []
        for device in ["fenix847mm", "fr265", "vivoactive5", "fenix7", "venusq2"]:
            data = dict(SCENARIOS["phishing"], demo=True)
            screen = render(device, data, theme)
            screen.save(out_dir / f"device-{device}.png")
            device_images.append(with_bezel(screen, DEVICES[device]["label"]))
        strip(device_images).save(out_dir / "devices.png")

        render_glance(dict(SCENARIOS["phishing"], demo=True), theme).save(out_dir / "glance.png")

        print(f"náhledy uloženy do {out_dir}")
        return 0

    data = load_data(args)
    screen = render(args.device, data, theme)
    image = screen if args.no_bezel else with_bezel(screen, DEVICES[args.device]["label"])
    out = pathlib.Path(args.out) if args.out else out_dir / f"{args.device}-{args.scenario}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
