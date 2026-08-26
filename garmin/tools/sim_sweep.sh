#!/usr/bin/env bash
# Projde zařízení z manifestu, každé spustí v simulátoru a uloží snímek
# obrazovky - kontrola, že se palubovka na daném displeji nerozsype.
#
#   garmin/tools/sim_sweep.sh                       # všechna zařízení
#   garmin/tools/sim_sweep.sh edge830 edge1050      # jen vyjmenovaná
#
# Snímky jdou do /tmp/sim-sweep. Potřebuje běžící X (DISPLAY).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${SWEEP_OUT:-/tmp/sim-sweep}"
PROJECT="${PROJECT:-RideDashboard}"
mkdir -p "$OUT"

if [ "$#" -gt 0 ]; then
    devices=("$@")
else
    mapfile -t devices < <(grep -o '<iq:product id="[^"]*"' "$HERE/$PROJECT/manifest.xml" | cut -d'"' -f2)
fi

for device in "${devices[@]}"; do
    printf '==> %-20s ' "$device"
    if "$HERE/tools/sim_shot.sh" "$device" "$PROJECT" "$OUT/$device.png" >/dev/null 2>&1; then
        echo "$OUT/$device.png"
    else
        echo "CHYBA"
    fi
done
