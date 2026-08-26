#!/usr/bin/env bash
# Spustí aplikaci v simulátoru a uloží snímek jeho okna.
#
#   garmin/tools/sim_shot.sh edge830 RideDashboard /tmp/edge830.png
#
# Potřebuje běžící X (DISPLAY) a simulátor si spustí sám, když neběží.
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
# shellcheck source=/dev/null
[ -f "$CIQ_HOME/env.sh" ] && source "$CIQ_HOME/env.sh"

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:?zařízení}"
PROJECT="${2:-RideDashboard}"
OUT="${3:-/tmp/$PROJECT-$DEVICE.png}"
export DISPLAY="${DISPLAY:-:1}"

"$HERE/build.sh" "$DEVICE" "$PROJECT" >/dev/null

# Simulátor drží jedno zařízení - po přepnutí je potřeba ho restartovat,
# jinak by monkeydo nahrál build do cizího přístroje.
pkill -f "$CIQ_SDK/bin/simulator" >/dev/null 2>&1 || true
sleep 2
"$CIQ_SDK/bin/simulator" >/tmp/ciq-simulator.log 2>&1 &
sleep 6

monkeydo "$HERE/$PROJECT/bin/$PROJECT-$DEVICE.prg" "$DEVICE" >/tmp/monkeydo-$DEVICE.log 2>&1 &
sleep 14

window="$(xdotool search --name "CIQ Simulator" | head -1)"
if [ -z "$window" ]; then
    echo "okno simulátoru se nenašlo" >&2
    exit 1
fi
import -window "$window" "$OUT"
echo "$OUT"
