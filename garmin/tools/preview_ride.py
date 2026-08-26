#!/usr/bin/env python3
"""Náhled jízdního dashboardu (Edge 1050, 480x800) bez simulátoru.

Čte stejné `RideDashboard/resources/json/layout.json` jako hodinková aplikace
a opakuje kreslicí postup z `source/DashboardView.mc`, takže se dá rozvržení
ladit bez device packů.

    python3 garmin/tools/preview_ride.py
    python3 garmin/tools/preview_ride.py --map --out /tmp/ride-map.png
    python3 garmin/tools/preview_ride.py --json data.json --out /tmp/ride.png

S `--map` je uprostřed ilustrace kartografie, kterou na přístroji kreslí
MapTrackView; bez ní drobečková stopa z GPS bodů, která funguje i na
jednotkách bez map.
"""

from __future__ import annotations

import argparse
import json
import math
import pathlib

from PIL import Image, ImageDraw, ImageFont

PROJECT_DIR = pathlib.Path(__file__).resolve().parents[1] / "RideDashboard"
LAYOUT_PATH = PROJECT_DIR / "resources" / "json" / "layout.json"

SUPERSAMPLE = 3

FONTS = {
    "regular": "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "bold": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "mono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
}

DEMO = {
    "clock": "14:32",
    "speed": 32.4,
    "avgSpeed": 24.6,
    "maxSpeed": 58.2,
    "cadence": 92,
    "heading": 142,
    "assistRange": 48.2,
    "assistBattery": 63,
    "distanceToDestination": 12.4,
    "eta": "15:04",
    "distance": 37.8,
    "ascent": 640,
    "descent": 512,
    "temperature": 18,
    "weather": "cloudy",
    "deviceBattery": 87,
}

WEATHER_LABELS = {"clear": "JASNO", "cloudy": "OBLAČNO", "rain": "DÉŠŤ"}
CARDINALS = ["S", "SV", "V", "JV", "J", "JZ", "Z", "SZ"]


def load_layout() -> dict:
    return json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))


def rgb(value: int) -> tuple[int, int, int]:
    return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)


def font(weight: str, pixels: int) -> ImageFont.FreeTypeFont:
    path = FONTS[weight]
    if pathlib.Path(path).exists():
        return ImageFont.truetype(path, pixels)
    return ImageFont.load_default()


class Painter:
    """Kreslení v souřadnicích návrhového plátna 480x800."""

    def __init__(self, layout: dict, scale: int = SUPERSAMPLE):
        self.layout = layout
        self.colors = layout["colors"]
        self.scale = scale
        canvas = layout["canvas"]
        self.image = Image.new(
            "RGB",
            (canvas["width"] * scale, canvas["height"] * scale),
            rgb(self.colors["background"]),
        )
        self.draw = ImageDraw.Draw(self.image)

    def color(self, name) -> tuple[int, int, int]:
        """Jméno barvy z layout.json, nebo rovnou RGB trojice."""
        if isinstance(name, tuple):
            return name
        return rgb(self.colors[name])

    def s(self, value: float) -> float:
        return value * self.scale

    def panel(self, x, y, width, height, radius=10, fill="panel", edge="panelEdge") -> None:
        self.draw.rounded_rectangle(
            (self.s(x), self.s(y), self.s(x + width) - 1, self.s(y + height) - 1),
            radius=self.s(radius),
            fill=self.color(fill),
            outline=self.color(edge),
            width=max(1, round(self.s(1))),
        )

    def text(self, x, y, value, size, weight="regular", color="text", anchor="mm") -> None:
        self.draw.text(
            (self.s(x), self.s(y)),
            value,
            font=font(weight, round(self.s(size))),
            fill=self.color(color),
            anchor=anchor,
        )

    def line(self, x1, y1, x2, y2, color="panelEdge", width=1) -> None:
        self.draw.line(
            (self.s(x1), self.s(y1), self.s(x2), self.s(y2)),
            fill=self.color(color),
            width=max(1, round(self.s(width))),
        )

    def arc(self, cx, cy, radius, start_deg, end_deg, color, pen) -> None:
        box = (self.s(cx - radius), self.s(cy - radius), self.s(cx + radius), self.s(cy + radius))
        self.draw.arc(box, start=start_deg, end=end_deg, fill=self.color(color), width=round(self.s(pen)))

    def bar(self, x, y, width, height, ratio, color) -> None:
        self.draw.rectangle(
            (self.s(x), self.s(y), self.s(x + width), self.s(y + height)),
            fill=self.color("panelEdge"),
        )
        filled = width * min(max(ratio, 0.0), 1.0)
        if filled > 0:
            self.draw.rectangle(
                (self.s(x), self.s(y), self.s(x + filled), self.s(y + height)),
                fill=self.color(color),
            )

    def polygon(self, points, color) -> None:
        self.draw.polygon([(self.s(px), self.s(py)) for px, py in points], fill=self.color(color))

    def rectangle(self, x, y, width, height, color) -> None:
        self.draw.rectangle(
            (self.s(x), self.s(y), self.s(x + width), self.s(y + height)),
            fill=self.color(color),
        )

    def frame(self, x, y, width, height, color, width_px=2) -> None:
        self.draw.rectangle(
            (self.s(x), self.s(y), self.s(x + width), self.s(y + height)),
            outline=self.color(color),
            width=max(1, round(self.s(width_px))),
        )

    def polyline(self, points, color, width) -> None:
        if len(points) < 2:
            return
        self.draw.line(
            [(self.s(px), self.s(py)) for px, py in points],
            fill=self.color(color),
            width=max(1, round(self.s(width))),
            joint="curve",
        )

    def text_width(self, value, size, weight="regular") -> float:
        return self.draw.textlength(value, font=font(weight, round(self.s(size)))) / self.scale

    def circle(self, cx, cy, radius, fill=None, outline=None, width=1) -> None:
        box = (self.s(cx - radius), self.s(cy - radius), self.s(cx + radius), self.s(cy + radius))
        self.draw.ellipse(
            box,
            fill=self.color(fill) if fill else None,
            outline=self.color(outline) if outline else None,
            width=max(1, round(self.s(width))),
        )

    def finish(self) -> Image.Image:
        canvas = self.layout["canvas"]
        return self.image.resize((canvas["width"], canvas["height"]), Image.LANCZOS)


def cadence_color(cadence: int, maximum: int) -> str:
    if cadence < 50:
        return "textDim"
    if cadence <= 100:
        return "ok"
    if cadence <= 150:
        return "warn"
    return "danger"


def draw_clock(p: Painter, data: dict) -> None:
    clock = p.layout["clock"]
    center = clock["y"] + clock["height"] / 2
    p.text(240, center, data["clock"], 30, "mono", "text")
    p.text(14, center, "GPS", 13, "bold", "ok", anchor="lm")
    p.text(466, center, f"{int(data['deviceBattery'])}%", 13, "regular", "textDim", anchor="rm")


def draw_cadence(p: Painter, data: dict) -> None:
    spec = p.layout["cadence"]
    cx, cy, radius, pen = spec["cx"], spec["cy"], spec["radius"], spec["pen"]
    cadence = int(data["cadence"])
    maximum = spec["max"]

    # Půlkruh vede zleva (0) přes vrchol do prava (max); Pillow měří úhly po
    # směru hodinových ručiček od tří hodin, takže horní půlkruh je 180..360.
    p.arc(cx, cy, radius, 180, 360, "panelEdge", pen)
    sweep = 180.0 * min(max(cadence / float(maximum), 0.0), 1.0)
    if sweep > 0.5:
        p.arc(cx, cy, radius, 180, 180 + sweep, cadence_color(cadence, maximum), pen)

    for tick in spec["ticks"]:
        angle = math.radians(180.0 + 180.0 * tick / float(maximum))
        outer = radius - pen - 3
        inner = outer - 9
        p.line(
            cx + outer * math.cos(angle), cy + outer * math.sin(angle),
            cx + inner * math.cos(angle), cy + inner * math.sin(angle),
            "textDim", 2,
        )

    # Popisky jen u krajních hodnot - uvnitř oblouku je místo pro tachometr.
    p.text(cx - radius + pen / 2, cy + 16, "0", 13, "regular", "textDim")
    p.text(cx + radius - pen / 2, cy + 16, str(maximum), 13, "regular", "textDim")

    p.text(cx, spec["labelY"], str(cadence), 32, "bold", cadence_color(cadence, maximum))
    p.text(cx, spec["unitY"], "KADENCE rpm", 13, "regular", "textDim")


def draw_speed(p: Painter, data: dict) -> None:
    """Tachometr: celá čísla velká, desetinné místo menší - jako na palubovce."""
    spec = p.layout["speed"]
    whole, _, decimal = f"{data['speed']:.1f}".partition(".")
    big, small = 106, 46

    whole_width = p.text_width(whole, big, "mono")
    decimal_width = p.text_width("." + decimal, small, "mono")
    left = 240 - (whole_width + decimal_width) / 2

    p.text(left, spec["cy"], whole, big, "mono", "text", anchor="lm")
    p.text(left + whole_width, spec["cy"] + 22, "." + decimal, small, "mono", "text", anchor="lm")
    p.text(240, spec["unitY"], "km/h", 20, "regular", "textDim")


def draw_speed_stats(p: Painter, data: dict) -> None:
    spec = p.layout["speedStats"]
    canvas = p.layout["canvas"]
    width = (canvas["width"] - 2 * spec["margin"] - spec["gap"]) / 2
    cells = [
        ("PRŮMĚR", f"{data['avgSpeed']:.1f}", "accent"),
        ("MAXIMUM", f"{data['maxSpeed']:.1f}", "warn"),
    ]
    for index, (label, value, color) in enumerate(cells):
        x = spec["margin"] + index * (width + spec["gap"])
        p.panel(x, spec["y"], width, spec["height"])
        p.text(x + 12, spec["y"] + spec["height"] / 2, label, 13, "regular", "textDim", anchor="lm")
        p.text(x + width - 42, spec["y"] + spec["height"] / 2, value, 28, "mono", color, anchor="rm")
        p.text(x + width - 12, spec["y"] + spec["height"] / 2 + 2, "km/h", 11, "regular", "textDim", anchor="rm")


def draw_compass(p: Painter, data: dict, box) -> None:
    x, y, width, height = box
    p.panel(x, y, width, height)
    p.text(x + width / 2, y + 16, "KOMPAS", 12, "regular", "textDim")

    heading = float(data["heading"])
    cx, cy = x + width / 2, y + height / 2 + 4
    radius = width / 2 - 14
    p.circle(cx, cy, radius, outline="panelEdge", width=2)

    # Nahoře je vždy směr jízdy, růžice se otáčí pod ním.
    for index, name in enumerate(["S", "V", "J", "Z"]):
        angle = math.radians(index * 90 - heading - 90)
        rx, ry = cx + (radius - 13) * math.cos(angle), cy + (radius - 13) * math.sin(angle)
        p.text(rx, ry, name, 14, "bold", "text" if name == "S" else "textDim")

    tip = math.radians(-90)
    left = math.radians(-90 + 140)
    right = math.radians(-90 - 140)
    needle = radius - 28
    p.polygon(
        [
            (cx + needle * math.cos(tip), cy + needle * math.sin(tip)),
            (cx + needle * 0.55 * math.cos(left), cy + needle * 0.55 * math.sin(left)),
            (cx, cy),
            (cx + needle * 0.55 * math.cos(right), cy + needle * 0.55 * math.sin(right)),
        ],
        "accent",
    )

    cardinal = CARDINALS[int((heading + 22.5) % 360 // 45)]
    p.text(cx, y + height - 16, f"{int(heading)}°  {cardinal}", 15, "bold", "text")


def draw_metric(p: Painter, box, label, value, unit, color, note=None, ratio=None) -> None:
    x, y, width, height = box
    p.panel(x, y, width, height)
    p.text(x + width / 2, y + 16, label, 12, "regular", "textDim")
    p.text(x + width / 2, y + height / 2 - 4, value, 34, "mono", color)
    p.text(x + width / 2, y + height / 2 + 26, unit, 13, "regular", "textDim")
    if ratio is not None:
        p.bar(x + 16, y + height - 30, width - 32, 6, ratio, color)
    if note:
        p.text(x + width / 2, y + height - 14, note, 12, "regular", "textDim")


def draw_map(p: Painter, data: dict, box) -> None:
    x, y, width, height = box
    p.panel(x, y, width, height, radius=12)

    spec = p.layout["map"]
    padding = spec["padding"]
    inner = (x + padding, y + padding, width - 2 * padding, height - 2 * padding)

    # Jemná mřížka, aby plocha působila jako mapový podklad.
    for step in range(1, 5):
        grid_y = y + height * step / 5.0
        p.line(x + 4, grid_y, x + width - 4, grid_y, "panelEdge", 1)
    for step in range(1, 4):
        grid_x = x + width * step / 4.0
        p.line(grid_x, y + 4, grid_x, y + height - 4, "panelEdge", 1)

    route = data.get("route") or demo_route()
    travelled = data.get("track") or route[: int(len(route) * 0.62)]

    points = route + travelled
    min_x = min(px for px, _ in points)
    max_x = max(px for px, _ in points)
    min_y = min(py for _, py in points)
    max_y = max(py for _, py in points)
    span = max(max_x - min_x, max_y - min_y, 1e-6)
    scale = min(inner[2], inner[3]) / span
    offset_x = inner[0] + (inner[2] - (max_x - min_x) * scale) / 2
    offset_y = inner[1] + (inner[3] - (max_y - min_y) * scale) / 2

    def project(point):
        px, py = point
        return offset_x + (px - min_x) * scale, offset_y + (max_y - py) * scale

    p.polyline([project(point) for point in route], "panelEdge", spec["routePen"] + 2)
    p.polyline([project(point) for point in travelled], "accent", spec["trackPen"])

    here = project(travelled[-1])
    previous = project(travelled[-2]) if len(travelled) > 1 else (here[0], here[1] + 1)
    angle = math.atan2(here[1] - previous[1], here[0] - previous[0])
    size = spec["markerRadius"] + 3
    p.polygon(
        [
            (here[0] + size * math.cos(angle), here[1] + size * math.sin(angle)),
            (here[0] + size * math.cos(angle + 2.5), here[1] + size * math.sin(angle + 2.5)),
            (here[0] + size * 0.4 * math.cos(angle + math.pi), here[1] + size * 0.4 * math.sin(angle + math.pi)),
            (here[0] + size * math.cos(angle - 2.5), here[1] + size * math.sin(angle - 2.5)),
        ],
        "text",
    )

    destination = project(route[-1])
    p.circle(destination[0], destination[1], 5, fill="danger")

    p.text(x + width - 16, y + 18, "S", 13, "bold", "textDim")
    p.line(x + width - 16, y + 24, x + width - 16, y + 34, "textDim", 2)
    p.line(x + 14, y + height - 16, x + 64, y + height - 16, "textDim", 2)
    p.text(x + 68, y + height - 17, "200 m", 11, "regular", "textDim", anchor="lm")


MOCK_MAP = {
    "land": (26, 29, 34),
    "forest": (24, 42, 33),
    "water": (18, 42, 66),
    "minor": (58, 64, 74),
    "major": (124, 132, 144),
    "highway": (150, 118, 58),
    "block": (36, 40, 46),
}

# Ilustrační kartografie v souřadnicích mapového okna 228x384. Na přístroji ji
# kreslí MapTrackView z map v paměti - tady jde jen o to, aby náhled ukázal,
# jak palubovka nad mapou vypadá.
MOCK_ROADS = [
    ("water", 13, [(-20, 30), (40, 80), (58, 170), (120, 235), (140, 330), (200, 400)]),
    ("highway", 7, [(-20, 315), (55, 262), (108, 215), (158, 138), (250, 52)]),
    ("major", 5, [(-20, 118), (72, 132), (142, 108), (250, 128)]),
    ("major", 4, [(96, -20), (104, 120), (86, 220), (108, 400)]),
    ("minor", 3, [(-20, 200), (60, 196), (96, 205)]),
    ("minor", 3, [(104, 285), (170, 278), (250, 292)]),
    ("minor", 3, [(30, 60), (34, 196)]),
    ("minor", 3, [(168, 20), (176, 110), (152, 168)]),
    ("minor", 3, [(190, 190), (250, 186)]),
]

MOCK_BLOCKS = [(18, 210, 30, 26), (56, 214, 26, 22), (112, 300, 34, 24), (180, 200, 28, 30)]


def draw_device_map(p: Painter, data: dict, box) -> None:
    """Mapové okno tak, jak ho vykreslí MapTrackView, s palubovkou nad ním."""
    x, y, width, height = box
    scale = p.scale
    tile = Image.new("RGB", (round(width * scale), round(height * scale)), MOCK_MAP["land"])
    pen = ImageDraw.Draw(tile)

    pen.ellipse(
        (-30 * scale, 250 * scale, 90 * scale, 400 * scale),
        fill=MOCK_MAP["forest"],
    )
    for bx, by, bw, bh in MOCK_BLOCKS:
        pen.rectangle((bx * scale, by * scale, (bx + bw) * scale, (by + bh) * scale), fill=MOCK_MAP["block"])
    for color, road_width, points in MOCK_ROADS:
        pen.line(
            [(px * scale, py * scale) for px, py in points],
            fill=MOCK_MAP[color],
            width=max(1, round(road_width * scale)),
            joint="curve",
        )
    p.image.paste(tile, (round(x * scale), round(y * scale)))

    # Stopa a šipka polohy - to kreslí aplikace jako MapPolyline nad mapou.
    route = data.get("route") or demo_route()
    travelled = data.get("track") or route[: int(len(route) * 0.62)]
    padding = p.layout["map"]["padding"]
    points = route + travelled
    min_x = min(px for px, _ in points)
    max_x = max(px for px, _ in points)
    min_y = min(py for _, py in points)
    max_y = max(py for _, py in points)
    span = max(max_x - min_x, max_y - min_y, 1e-6)
    factor = min(width - 2 * padding, height - 2 * padding) / span
    offset_x = x + padding + (width - 2 * padding - (max_x - min_x) * factor) / 2
    offset_y = y + padding + (height - 2 * padding - (max_y - min_y) * factor) / 2

    def project(point):
        px, py = point
        return offset_x + (px - min_x) * factor, offset_y + (max_y - py) * factor

    p.polyline([project(point) for point in travelled], "accent", p.layout["map"]["trackPen"])
    here = project(travelled[-1])
    previous = project(travelled[-2]) if len(travelled) > 1 else (here[0], here[1] + 1)
    angle = math.atan2(here[1] - previous[1], here[0] - previous[0])
    size = p.layout["map"]["markerRadius"] + 3
    p.polygon(
        [
            (here[0] + size * math.cos(angle), here[1] + size * math.sin(angle)),
            (here[0] + size * math.cos(angle + 2.5), here[1] + size * math.sin(angle + 2.5)),
            (here[0] + size * 0.4 * math.cos(angle + math.pi), here[1] + size * 0.4 * math.sin(angle + math.pi)),
            (here[0] + size * math.cos(angle - 2.5), here[1] + size * math.sin(angle - 2.5)),
        ],
        "text",
    )

    strip = 18
    p.rectangle(x + 1, y + height - strip, width - 2, strip - 1, "panel")
    p.text(x + width / 2, y + height - strip / 2, "MAPA · výběr = přes celou obrazovku", 11,
           "regular", "textDim")
    p.frame(x, y, width, height, "panelEdge", 2)


def demo_route():
    points = []
    for step in range(90):
        t = step / 89.0
        points.append((
            math.sin(t * 3.6) * 1.5 + t * 3.4,
            math.cos(t * 2.4) * 1.1 + t * 5.2,
        ))
    return points


def draw_bottom(p: Painter, data: dict) -> None:
    spec = p.layout["bottom"]
    canvas = p.layout["canvas"]
    count = 4
    width = (canvas["width"] - 2 * spec["margin"] - (count - 1) * spec["gap"]) / count
    y, height = spec["y"], spec["height"]

    cells = [
        ("E-BIKE", f"{int(data['assistBattery'])}%", "ok" if data["assistBattery"] > 30 else "danger"),
        ("NASTOUPÁNO", f"{int(data['ascent'])} m", "warn"),
        ("SESTOUPÁNO", f"{int(data['descent'])} m", "cold"),
        (WEATHER_LABELS.get(data["weather"], "POČASÍ"), f"{int(data['temperature'])}°C", "text"),
    ]

    for index, (label, value, color) in enumerate(cells):
        x = spec["margin"] + index * (width + spec["gap"])
        p.panel(x, y, width, height)
        p.text(x + width / 2, y + 15, label, 11, "regular", "textDim")
        p.text(x + width / 2, y + 34, value, 21, "mono", color)

    battery_x = spec["margin"]
    p.bar(battery_x + 12, y + height - 9, width - 24, 4, data["assistBattery"] / 100.0,
          "ok" if data["assistBattery"] > 30 else "danger")

    weather_x = spec["margin"] + 3 * (width + spec["gap"])
    draw_weather_icon(p, weather_x + 14, y + height / 2 + 2, data["weather"])


def draw_weather_icon(p: Painter, cx, cy, weather) -> None:
    if weather == "clear":
        p.circle(cx, cy, 7, fill="warn")
        return
    if weather == "rain":
        p.circle(cx - 4, cy - 2, 5, fill="textDim")
        p.circle(cx + 3, cy - 3, 6, fill="textDim")
        for offset in (-4, 1, 6):
            p.line(cx + offset, cy + 4, cx + offset - 2, cy + 9, "cold", 2)
        return
    p.circle(cx + 4, cy - 5, 5, fill="warn")
    p.circle(cx - 4, cy + 1, 5, fill="textDim")
    p.circle(cx + 3, cy + 1, 6, fill="textDim")


def render(data: dict, layout: dict, device_map: bool = False) -> Image.Image:
    p = Painter(layout)

    draw_clock(p, data)
    draw_cadence(p, data)
    draw_speed(p, data)
    draw_speed_stats(p, data)
    p.line(8, layout["divider"]["y"], 472, layout["divider"]["y"], "panelEdge", 1)

    middle = layout["middle"]
    canvas = layout["canvas"]
    top, bottom = middle["top"], middle["bottom"]
    side = middle["sideWidth"]
    margin, gap = middle["margin"], middle["gap"]
    cell_height = (bottom - top - gap) / 2
    map_x = margin + side + gap
    map_width = canvas["width"] - 2 * (margin + side + gap)
    right_x = canvas["width"] - margin - side

    draw_compass(p, data, (margin, top, side, cell_height))
    draw_metric(
        p, (margin, top + cell_height + gap, side, cell_height),
        "DOJEZD E-BIKE", f"{data['assistRange']:.0f}", "km", "ok",
        ratio=data["assistBattery"] / 100.0,
    )
    draw_metric(
        p, (right_x, top, side, cell_height),
        "DO CÍLE", f"{data['distanceToDestination']:.1f}", "km", "accent",
        note=f"příjezd {data['eta']}",
    )
    draw_metric(
        p, (right_x, top + cell_height + gap, side, cell_height),
        "NAJETO", f"{data['distance']:.1f}", "km", "text",
    )
    if device_map:
        draw_device_map(p, data, (map_x, top, map_width, bottom - top))
    else:
        draw_map(p, data, (map_x, top, map_width, bottom - top))

    draw_bottom(p, data)
    return p.finish()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", help="soubor s daty (klíče jako v DEMO)")
    parser.add_argument("--out", default="garmin/docs/preview/ride-edge1050.png")
    parser.add_argument(
        "--map",
        action="store_true",
        help="režim s mapou z paměti přístroje (RideMapView) místo drobečkové stopy",
    )
    args = parser.parse_args()

    data = dict(DEMO)
    if args.json:
        data.update(json.loads(pathlib.Path(args.json).read_text(encoding="utf-8")))

    image = render(data, load_layout(), device_map=args.map)
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
