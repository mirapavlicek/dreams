#!/usr/bin/env bash
# Přeloží dashboard proti náhradní definici zařízení - kontrola syntaxe a typů,
# která nepotřebuje Garmin účet ani stažené device packy.
#
#   ./garmin/check.sh            # výchozí kontrola typů
#   ./garmin/check.sh -l 2       # ukecanější typová analýza
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
# shellcheck source=/dev/null
[ -f "$CIQ_HOME/env.sh" ] && source "$CIQ_HOME/env.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="$(python3 "$HERE/tools/stub_device.py")"

# Manifest smí obsahovat jen skutečně stažená zařízení, takže náhradní id
# přidáme do dočasné kopie projektu a originál necháme být.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cp -r "$HERE/QMailDashboard" "$workdir/project"
python3 - "$workdir/project/manifest.xml" "$DEVICE" <<'PY'
import pathlib, sys
path, device = pathlib.Path(sys.argv[1]), sys.argv[2]
path.write_text(path.read_text().replace(
    "<iq:products>", f'<iq:products>\n            <iq:product id="{device}"/>'))
PY

"$CIQ_SDK/bin/monkeyc" \
    --jungles "$workdir/project/monkey.jungle" \
    --device "$DEVICE" \
    --output "$workdir/check.prg" \
    --private-key "$CIQ_DEVELOPER_KEY" \
    --warn \
    "$@" 2>&1 | grep -vE "Invalid device id found|Glance applications are not supported"

echo "OK: kód se přeložil proti $DEVICE"
