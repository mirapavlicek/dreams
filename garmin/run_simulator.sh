#!/usr/bin/env bash
# Přeloží projekt a nahraje ho do Connect IQ simulátoru.
#
#   ./garmin/run_simulator.sh fenix847mm                # QMailDashboard
#   ./garmin/run_simulator.sh edge1050 RideDashboard
#
# Na headless stroji je potřeba mít X server, např.:
#   Xvfb :1 -screen 0 1280x1024x24 & export DISPLAY=:1
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
# shellcheck source=/dev/null
[ -f "$CIQ_HOME/env.sh" ] && source "$CIQ_HOME/env.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${1:-fenix847mm}"
PROJECT="${2:-QMailDashboard}"
PRG="$HERE/$PROJECT/bin/$PROJECT-$DEVICE.prg"

"$HERE/build.sh" "$DEVICE" "$PROJECT"

if ! pgrep -f "$CIQ_SDK/bin/simulator" >/dev/null 2>&1; then
    echo "==> spouštím simulátor"
    "$CIQ_SDK/bin/simulator" >/tmp/ciq-simulator.log 2>&1 &
    sleep 5
fi

echo "==> nahrávám $PRG"
exec "$CIQ_SDK/bin/monkeydo" "$PRG" "$DEVICE"
