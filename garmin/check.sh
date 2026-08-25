#!/usr/bin/env bash
# Přeloží projekty proti náhradní definici zařízení - kontrola syntaxe a typů,
# která nepotřebuje Garmin účet ani stažené device packy.
#
#   ./garmin/check.sh                    # oba projekty
#   ./garmin/check.sh RideDashboard      # jen jeden
#   ./garmin/check.sh RideDashboard -l 2 # ukecanější typová analýza
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
# shellcheck source=/dev/null
[ -f "$CIQ_HOME/env.sh" ] && source "$CIQ_HOME/env.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"

PROJECTS=()
case "${1:-}" in
    QMailDashboard|RideDashboard) PROJECTS=("$1"); shift ;;
    *) PROJECTS=(QMailDashboard RideDashboard) ;;
esac

check_project() {
    local project="$1"; shift
    local device

    case "$project" in
        QMailDashboard) device="$(python3 "$HERE/tools/stub_device.py" --id qmailstub --shape round --width 454 --height 454)" ;;
        RideDashboard)  device="$(python3 "$HERE/tools/stub_device.py" --id ridestub --shape rectangle --width 480 --height 800)" ;;
    esac

    # Manifest smí obsahovat jen skutečně stažená zařízení, takže náhradní id
    # přidáme do dočasné kopie projektu a originál necháme být.
    local workdir
    workdir="$(mktemp -d)"
    cp -r "$HERE/$project" "$workdir/project"
    python3 - "$workdir/project/manifest.xml" "$device" <<'PY'
import pathlib, sys
path, device = pathlib.Path(sys.argv[1]), sys.argv[2]
path.write_text(path.read_text().replace(
    "<iq:products>", f'<iq:products>\n            <iq:product id="{device}"/>'))
PY

    echo "==> $project ($device)"
    "$CIQ_SDK/bin/monkeyc" \
        --jungles "$workdir/project/monkey.jungle" \
        --device "$device" \
        --output "$workdir/check.prg" \
        --private-key "$CIQ_DEVELOPER_KEY" \
        --warn \
        "$@" 2>&1 | grep -vE "Invalid device id found|Glance applications are not supported" || true

    if [ ! -f "$workdir/check.prg" ]; then
        rm -rf "$workdir"
        echo "CHYBA: $project se nepřeložil" >&2
        return 1
    fi
    rm -rf "$workdir"
}

for project in "${PROJECTS[@]}"; do
    check_project "$project" "$@"
done

echo "OK: překlad prošel"
