#!/usr/bin/env python3
"""Vyrobí náhradní definici zařízení, aby šel kód přeložit bez Garmin účtu.

`monkeyc` odmítne pracovat bez device packu (`-d` je povinné), a ty jsou u
Garminu za přihlášením. Pro kontrolu syntaxe a typů ale stačí málo: vlastnoručně
napsaný `compiler.json` s rozlišením a limity paměti. Tenhle skript ho zapíše do
~/.Garmin/ConnectIQ/Devices/qmailstub a `garmin/check.sh` proti němu překládá.

Není to náhrada skutečného zařízení - simulátor potřebuje navíc Garmin fonty,
takže spustit aplikaci proti téhle definici nejde. Slouží jen k překladu.
"""

from __future__ import annotations

import json
import pathlib

DEVICE_ID = "qmailstub"
DEVICE_DIR = pathlib.Path.home() / ".Garmin" / "ConnectIQ" / "Devices" / DEVICE_ID

COMPILER_JSON = {
    "deviceId": DEVICE_ID,
    "displayName": "qmail build stub (454x454)",
    "deviceFamily": "round-454x454",
    "worldWidePartNumber": "006-B9999-00",
    "bitsPerPixel": 24,
    "orientation": "landscape",
    "resolution": {"width": 454, "height": 454},
    "launcherIcon": {"width": 40, "height": 40},
    "imageFormats": ["png"],
    "antiAliasedFontSupport": True,
    "alphaBlendingSupport": "FULL",
    "appTypes": [{"type": "watchApp", "memoryLimit": 1048576, "prgLimit": 8388608}],
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
    DEVICE_DIR.mkdir(parents=True, exist_ok=True)
    (DEVICE_DIR / "compiler.json").write_text(json.dumps(COMPILER_JSON, indent=2), encoding="utf-8")
    (DEVICE_DIR / "simulator.json").write_text(json.dumps(SIMULATOR_JSON, indent=2), encoding="utf-8")
    print(DEVICE_ID)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
