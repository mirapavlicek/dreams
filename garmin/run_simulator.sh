#!/usr/bin/env bash
# Přeloží dashboard a nahraje ho do Connect IQ simulátoru.
#
#   ./garmin/run_simulator.sh            # fenix847mm
#   ./garmin/run_simulator.sh venu3
#
# Na headless stroji je potřeba mít X server, např.:
#   Xvfb :1 -screen 0 1280x1024x24 & export DISPLAY=:1
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
# shellcheck source=/dev/null
[ -f "$CIQ_HOME/env.sh" ] && source "$CIQ_HOME/env.sh"

DEVICE="${1:-fenix847mm}"
PROJECT_DIR="$(cd "$(dirname "$0")/QMailDashboard" && pwd)"
PRG="$PROJECT_DIR/bin/QMailDashboard-$DEVICE.prg"

"$(dirname "$0")/build.sh" "$DEVICE"

if ! pgrep -f "$CIQ_SDK/bin/simulator" >/dev/null 2>&1; then
    echo "==> spouštím simulátor"
    "$CIQ_SDK/bin/simulator" >/tmp/ciq-simulator.log 2>&1 &
    sleep 5
fi

echo "==> nahrávám $PRG"
exec "$CIQ_SDK/bin/monkeydo" "$PRG" "$DEVICE"
