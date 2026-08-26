#!/usr/bin/env python3
"""Vyrobí náhradní definici zařízení, aby šel kód přeložit bez Garmin účtu.

`monkeyc` odmítne pracovat bez device packu (`-d` je povinné), a ty jsou u
Garminu za přihlášením. Pro kontrolu syntaxe a typů ale stačí málo: vlastnoručně
napsaný `compiler.json` s rozlišením a limity paměti. Skript ho zapíše do
~/.Garmin/ConnectIQ/Devices/<id> a `garmin/check.sh` proti němu překládá.

Není to náhrada skutečného zařízení - simulátor potřebuje navíc Garmin fonty,
takže spustit aplikaci proti téhle definici nejde. Slouží jen k překladu.

    python3 garmin/tools/stub_device.py                              # 454x454 kulaté
    python3 garmin/tools/stub_device.py --id ridestub --shape rectangle --width 480 --height 800
"""

from __future__ import annotations

import argparse
import json
import pathlib

DEVICES_ROOT = pathlib.Path.home() / ".Garmin" / "ConnectIQ" / "Devices"


def compiler_json(device_id: str, shape: str, width: int, height: int) -> dict:
    return {
        "deviceId": device_id,
        "displayName": f"{device_id} ({width}x{height})",
        "deviceFamily": f"{shape}-{width}x{height}",
        "worldWidePartNumber": "006-B9999-00",
        "bitsPerPixel": 24,
        "orientation": "landscape" if width >= height else "portrait",
        "resolution": {"width": width, "height": height},
        "launcherIcon": {"width": 40, "height": 40},
        "imageFormats": ["png"],
        "antiAliasedFontSupport": True,
        "alphaBlendingSupport": "FULL",
        "appTypes": [
            {"type": "watchApp", "memoryLimit": 1048576, "prgLimit": 8388608},
            # Datové pole má na skutečném Edge osminový limit; kontrola překladu
            # se o něj neopírá, ale bez uvedeného typu by ho monkeyc odmítl.
            {"type": "datafield", "memoryLimit": 131072, "prgLimit": 8388608},
        ],
        "partNumbers": [
            {
                "number": "006-B9999-00",
                "connectIQVersion": "5.1.0",
                "firmwareVersion": 100,
                "languages": [{"code": "eng", "fontSet": "vivoactive"}],
            }
        ],
    }


SIMULATOR_JSON = {"fonts": [{"fontSet": "vivoactive", "fonts": []}], "layouts": []}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--id", default="qmailstub")
    parser.add_argument("--shape", default="round", choices=["round", "rectangle", "semi-round"])
    parser.add_argument("--width", type=int, default=454)
    parser.add_argument("--height", type=int, default=454)
    args = parser.parse_args()

    device_dir = DEVICES_ROOT / args.id
    device_dir.mkdir(parents=True, exist_ok=True)
    (device_dir / "compiler.json").write_text(
        json.dumps(compiler_json(args.id, args.shape, args.width, args.height), indent=2), encoding="utf-8"
    )
    (device_dir / "simulator.json").write_text(json.dumps(SIMULATOR_JSON, indent=2), encoding="utf-8")
    print(args.id)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
