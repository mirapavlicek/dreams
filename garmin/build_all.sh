#!/usr/bin/env bash
# Přeloží projekt pro všechna zařízení z manifestu a složí je do garmin/dist,
# odkud se dají rovnou nakopírovat do přístroje.
#
#   ./garmin/build_all.sh                     # RideDashboard pro celou řadu Edge
#   ./garmin/build_all.sh QMailDashboard      # hodinky
#   ./garmin/build_all.sh RideDashboard -r    # bez ladicích informací (menší .prg)
#
# Do jednotky patří vždy build přeložený přesně pro ni - cizí Edge tiše zahodí
# a poznámku o tom nechá jen v GARMIN/APPS/LOGS.
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
# shellcheck source=/dev/null
[ -f "$CIQ_HOME/env.sh" ] && source "$CIQ_HOME/env.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECT="RideDashboard"
if [ "${1:-}" = "QMailDashboard" ] || [ "${1:-}" = "RideDashboard" ]; then
    PROJECT="$1"
    shift
fi

MANIFEST="$HERE/$PROJECT/manifest.xml"
DIST="$HERE/dist/$PROJECT"
DEVICES_DIR="${HOME}/.Garmin/ConnectIQ/Devices"

mkdir -p "$DIST"
rm -f "$DIST"/*.prg "$DIST"/PREHLED.txt

mapfile -t devices < <(grep -o '<iq:product id="[^"]*"' "$MANIFEST" | cut -d'"' -f2)
if [ "${#devices[@]}" -eq 0 ]; then
    echo "v $MANIFEST nejsou žádná zařízení" >&2
    exit 1
fi

missing=()
built=()
for device in "${devices[@]}"; do
    if [ ! -f "$DEVICES_DIR/$device/compiler.json" ]; then
        missing+=("$device")
        continue
    fi
    printf '==> %-18s ' "$device"
    if "$HERE/build.sh" "$device" "$PROJECT" "$@" >"/tmp/build-$device.log" 2>&1; then
        cp "$HERE/$PROJECT/bin/$PROJECT-$device.prg" "$DIST/$PROJECT-$device.prg"
        printf 'ok (%s)\n' "$(du -h "$DIST/$PROJECT-$device.prg" | cut -f1)"
        built+=("$device")
    else
        printf 'CHYBA - viz /tmp/build-%s.log\n' "$device"
        exit 1
    fi
done

# Přehled patří k buildům, ne do hlavy: podle jména souboru není poznat, jestli
# je edge840 ten s displejem 246x322 nebo ne.
{
    echo "RideDashboard - který soubor do kterého přístroje"
    echo "vytvořeno: $(date '+%Y-%m-%d %H:%M')"
    echo
    printf '%-34s %-26s %-10s %s\n' "SOUBOR" "PŘÍSTROJ" "DISPLEJ" "ROZVRŽENÍ"
    for device in "${built[@]}"; do
        python3 - "$DEVICES_DIR/$device/compiler.json" "$PROJECT-$device.prg" <<'PY'
import json, sys
compiler = json.load(open(sys.argv[1]))
resolution = compiler["resolution"]
family = compiler["deviceFamily"]
compact = family in ("rectangle-246x322", "rectangle-240x320")
print("%-34s %-26s %-10s %s" % (
    sys.argv[2],
    compiler["displayName"],
    "%dx%d" % (resolution["width"], resolution["height"]),
    "kompaktní" if compact else "plné",
))
PY
    done
    echo
    echo "Nahrání: přístroj připoj USB kabelem, soubor zkopíruj do GARMIN/APPS"
    echo "a přístroj odpoj. Po odpojení soubor ze složky zmizí - firmware si ho"
    echo "přesune do vlastního úložiště."
} > "$DIST/PREHLED.txt"

echo
cat "$DIST/PREHLED.txt"

if [ "${#missing[@]}" -gt 0 ]; then
    echo
    echo "Přeskočeno (chybí device pack): ${missing[*]}"
    echo "Stáhni je: connect-iq-sdk-manager device download --manifest $MANIFEST --include-fonts"
fi
