#!/usr/bin/env bash
# Cloud Agent install: připraví vývojové prostředí pro qmail i Garmin projekty.
#
# Idempotentní - lze spustit opakovaně. Nainstaluje:
#   * Python nástroje: pytest (testy) a Pillow (náhledový renderer garmin/tools)
#   * Connect IQ SDK + podepisovací klíč pro kontrolu překladu (garmin/check.sh)
#
# Simulátor Connect IQ (garmin/run_simulator.sh) potřebuje navíc stažené device
# packy z Garmin developer účtu (GARMIN_USERNAME/GARMIN_PASSWORD, bez 2FA) a
# grafické prostředí - to se v cloudu nepřipravuje. Kontrola překladu přes
# náhradní zařízení (garmin/check.sh) i celý Python tok fungují bez účtu.
set -euo pipefail

log() { printf '\n==> %s\n' "$*"; }

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
SDK_VERSION="${CIQ_SDK_VERSION:-}"
SDKS_JSON_URL="https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json"
SDK_BASE_URL="https://developer.garmin.com/downloads/connect-iq/sdks"

log "Systémové balíčky (Python testy + náhledový renderer, překladač Connect IQ)"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3-pytest python3-pil \
    unzip curl openssl default-jre

log "Připraven Python tok (qmail + garmin/tools)"
python3 -m pytest --version
python3 -c "import PIL; print('Pillow', PIL.__version__)"

# --- Connect IQ SDK pro kontrolu překladu (garmin/check.sh) -----------------
# Vynechává webkit2gtk-4.0 z Ubuntu jammy, který setup_dev_env.sh instaluje jen
# kvůli GUI simulátoru; ten v cloudu bez Garmin účtu a displeje stejně neběží.
mkdir -p "$CIQ_HOME" "$CIQ_HOME/bin" "$CIQ_HOME/keys" "$CIQ_HOME/sdk"

if [ ! -x "$CIQ_HOME/sdk/bin/monkeyc" ]; then
    log "Connect IQ SDK"
    sdks_json="$(mktemp)"
    curl -fsSL "$SDKS_JSON_URL" -o "$sdks_json"
    sdk_file="$(SDK_VERSION="$SDK_VERSION" python3 - "$sdks_json" <<'PY'
import json, os, sys
wanted = os.environ.get("SDK_VERSION") or ""
sdks = json.load(open(sys.argv[1]))
match = [s for s in sdks if s["version"] == wanted] if wanted else sdks[-1:]
if not match:
    sys.exit(f"SDK {wanted} neni v seznamu ({', '.join(s['version'] for s in sdks)})")
print(match[0]["linux"])
PY
)"
    rm -f "$sdks_json"
    tmp_zip="$(mktemp --suffix=.zip)"
    curl -fL --progress-bar "$SDK_BASE_URL/$sdk_file" -o "$tmp_zip"
    unzip -q -o "$tmp_zip" -d "$CIQ_HOME/sdk"
    rm -f "$tmp_zip"
fi
"$CIQ_HOME/sdk/bin/monkeyc" --version

if [ ! -f "$CIQ_HOME/keys/developer_key.der" ]; then
    log "Podepisovací klíč vývojáře"
    openssl genrsa -out "$CIQ_HOME/keys/developer_key.pem" 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in "$CIQ_HOME/keys/developer_key.pem" \
        -out "$CIQ_HOME/keys/developer_key.der" -nocrypt
    chmod 600 "$CIQ_HOME/keys/developer_key.pem" "$CIQ_HOME/keys/developer_key.der"
fi

if [ ! -x "$CIQ_HOME/bin/connect-iq-sdk-manager" ]; then
    log "connect-iq-sdk-manager (stažení device packů po přihlášení k účtu)"
    curl -fsSL https://raw.githubusercontent.com/lindell/connect-iq-sdk-manager-cli/master/install.sh \
        | sh -s -- -b "$CIQ_HOME/bin" >/dev/null
fi

# env.sh dodá check.sh/build.sh cesty k SDK, klíči a nástrojům.
cat > "$CIQ_HOME/env.sh" <<EOF
# Načti přes: source $CIQ_HOME/env.sh
export CIQ_HOME="$CIQ_HOME"
export CIQ_SDK="\$CIQ_HOME/sdk"
export CIQ_DEVELOPER_KEY="\$CIQ_HOME/keys/developer_key.der"
export PATH="\$CIQ_SDK/bin:\$CIQ_HOME/bin:\$PATH"
EOF

log "Hotovo - qmail testy, náhledy i kontrola překladu Connect IQ jsou připravené"
