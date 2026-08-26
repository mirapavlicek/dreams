#!/usr/bin/env bash
# Přeloží projekt pro jedno zařízení.
#
#   ./garmin/build.sh fenix847mm                      # QMailDashboard
#   ./garmin/build.sh edge1050 RideDashboard          # aplikace
#   ./garmin/build.sh edge1050 RideField              # datové pole
#   ./garmin/build.sh edge1050 RideDashboard --release
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
# shellcheck source=/dev/null
[ -f "$CIQ_HOME/env.sh" ] && source "$CIQ_HOME/env.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
DEVICE="${1:-fenix847mm}"
shift || true

PROJECT="QMailDashboard"
if [ -n "${1:-}" ] && [ -f "$HERE/${1}/monkey.jungle" ]; then
    PROJECT="$1"
    shift
fi

PROJECT_DIR="$HERE/$PROJECT"
OUT_DIR="$PROJECT_DIR/bin"
mkdir -p "$OUT_DIR"

exec "$CIQ_SDK/bin/monkeyc" \
    --jungles "$PROJECT_DIR/monkey.jungle" \
    --device "$DEVICE" \
    --output "$OUT_DIR/$PROJECT-$DEVICE.prg" \
    --private-key "$CIQ_DEVELOPER_KEY" \
    --warn \
    "$@"
