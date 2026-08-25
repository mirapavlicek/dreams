#!/usr/bin/env python3
"""Přepíše <iq:products> v manifestu podle skutečně stažených device packů.

Seznam zařízení v manifestu musí odpovídat tomu, co je nainstalované v
~/.Garmin/ConnectIQ/Devices - jinak `monkeyc` skončí na "Invalid device id".
Po každém `connect-iq-sdk-manager device download` tedy stačí spustit:

    python3 garmin/tools/sync_devices.py            # všechna stažená zařízení
    python3 garmin/tools/sync_devices.py --check    # jen ověří, nic nemění
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

MANIFEST = pathlib.Path(__file__).resolve().parents[1] / "QMailDashboard" / "manifest.xml"
DEVICES_DIR = pathlib.Path.home() / ".Garmin" / "ConnectIQ" / "Devices"


def installed_devices() -> list[str]:
    if not DEVICES_DIR.is_dir():
        return []
    return sorted(path.name for path in DEVICES_DIR.iterdir() if (path / "compiler.json").exists())


def manifest_devices(text: str) -> list[str]:
    return re.findall(r'<iq:product\s+id="([^"]+)"\s*/>', text)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="jen porovnat, nezapisovat")
    args = parser.parse_args()

    devices = installed_devices()
    if not devices:
        print(f"v {DEVICES_DIR} nejsou žádné device packy - nejdřív je stáhni "
              f"(connect-iq-sdk-manager device download)", file=sys.stderr)
        return 1

    text = MANIFEST.read_text(encoding="utf-8")
    current = manifest_devices(text)

    missing = [device for device in current if device not in devices]
    if args.check:
        print(f"{len(devices)} stažených zařízení, {len(current)} v manifestu")
        if missing:
            print("v manifestu, ale nestažené: " + ", ".join(missing))
            return 1
        return 0

    block = "\n".join(f'            <iq:product id="{device}"/>' for device in devices)
    updated = re.sub(
        r"(<iq:products>)(.*?)(\s*</iq:products>)",
        lambda match: f"{match.group(1)}\n{block}\n        {match.group(3).strip()}",
        text,
        flags=re.DOTALL,
    )
    MANIFEST.write_text(updated, encoding="utf-8")
    print(f"manifest aktualizován na {len(devices)} zařízení")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
