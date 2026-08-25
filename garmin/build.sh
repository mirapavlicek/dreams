#!/usr/bin/env bash
# Přeloží dashboard pro jedno zařízení.
#
#   ./garmin/build.sh                 # výchozí zařízení fenix847mm
#   ./garmin/build.sh venu3
#   ./garmin/build.sh fenix847mm --release
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
# shellcheck source=/dev/null
[ -f "$CIQ_HOME/env.sh" ] && source "$CIQ_HOME/env.sh"

PROJECT_DIR="$(cd "$(dirname "$0")/QMailDashboard" && pwd)"
DEVICE="${1:-fenix847mm}"
shift || true

OUT_DIR="$PROJECT_DIR/bin"
mkdir -p "$OUT_DIR"

exec "$CIQ_SDK/bin/monkeyc" \
    --jungles "$PROJECT_DIR/monkey.jungle" \
    --device "$DEVICE" \
    --output "$OUT_DIR/QMailDashboard-$DEVICE.prg" \
    --private-key "$CIQ_DEVELOPER_KEY" \
    --warn \
    "$@"
