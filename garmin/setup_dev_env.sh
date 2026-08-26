#!/usr/bin/env bash
# Nainstaluje vývojové prostředí Garmin Connect IQ na Ubuntu (testováno na 24.04).
#
#   ./garmin/setup_dev_env.sh              # SDK, běhové závislosti simulátoru, klíč
#   ./garmin/setup_dev_env.sh 9.2.0        # konkrétní verze SDK
#
# Device packy (definice zařízení + fonty pro simulátor) Garmin nabízí jen po
# přihlášení k developer účtu. Když jsou v prostředí GARMIN_USERNAME a
# GARMIN_PASSWORD, skript je stáhne sám; jinak tenhle krok přeskočí a všechno
# ostatní (překladač, simulátor, podepisovací klíč) je připravené.
set -euo pipefail

CIQ_HOME="${CIQ_HOME:-$HOME/connectiq}"
WEBKIT_PREFIX="${WEBKIT_PREFIX:-/opt/webkit40}"
SDK_VERSION="${1:-}"
SDKS_JSON_URL="https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json"
SDK_BASE_URL="https://developer.garmin.com/downloads/connect-iq/sdks"

log() { printf '\n==> %s\n' "$*"; }

log "Systémové balíčky"
sudo apt-get update -qq
sudo apt-get install -y -qq \
    unzip curl openssl python3 python3-pil default-jre \
    libevdev2 libgstreamer-plugins-base1.0-0 libgstreamer-gl1.0-0 \
    libwayland-server0 libxslt1.1 libsecret-1-0 libnotify4 libgles2 \
    libgtk-3-0 libcanberra-gtk3-module

# Simulátor je slinkovaný proti webkit2gtk-4.0 (libsoup2), který v Ubuntu 24.04
# už není. Knihovny z jammy proto rozbalíme stranou a přidáme do LD_LIBRARY_PATH,
# ať se nemíchají se systémovými.
install_webkit40() {
    echo 'deb http://archive.ubuntu.com/ubuntu jammy main universe
deb http://archive.ubuntu.com/ubuntu jammy-updates main universe
deb http://security.ubuntu.com/ubuntu jammy-security main universe' \
        | sudo tee /etc/apt/sources.list.d/ciq-jammy.list >/dev/null
    # Pin -1 drží jammy balíčky mimo systém - proto se nesmí instalovat, jen
    # stahovat, a to jen s výslovně uvedeným původem (`pkg/jammy`); bez něj
    # apt kvůli pinu hlásí "no candidate".
    printf 'Package: *\nPin: release n=jammy*\nPin-Priority: -1\n' \
        | sudo tee /etc/apt/preferences.d/ciq-jammy >/dev/null
    sudo apt-get update -qq

    local workdir rc=0
    workdir="$(mktemp -d)"
    (
        cd "$workdir"
        for pkg in libwebkit2gtk-4.0-37 libjavascriptcoregtk-4.0-18 libsoup2.4-1 \
                   libsoup-gnome2.4-1 libicu70 libwoff1 libhyphen0 libenchant-2-2 \
                   libmanette-0.2-0 libharfbuzz-icu0; do
            apt-get download "$pkg/jammy-updates" >/dev/null 2>&1 \
                || apt-get download "$pkg/jammy-security" >/dev/null 2>&1 \
                || apt-get download "$pkg/jammy" >/dev/null
        done
        sudo mkdir -p "$WEBKIT_PREFIX"
        sudo chown "$(id -u):$(id -g)" "$WEBKIT_PREFIX"
        for deb in *.deb; do dpkg -x "$deb" "$WEBKIT_PREFIX"; done
    ) || rc=$?
    rm -rf "$workdir"
    return "$rc"
}

if [ ! -f "$WEBKIT_PREFIX/usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37" ]; then
    log "webkit2gtk-4.0 pro simulátor (z Ubuntu jammy, mimo systémové cesty)"
    # Knihovny potřebuje jen simulátor. Když je archiv nemá, překlad ani
    # podepisování to nezastaví, takže se jen ozveme a jede se dál.
    install_webkit40 || log "POZOR: webkit2gtk-4.0 se nepodařilo připravit, simulátor nepoběží (překlad ano)"
fi

log "Connect IQ SDK"
mkdir -p "$CIQ_HOME" "$CIQ_HOME/bin"
sdks_json="$(mktemp)"
curl -fsSL "$SDKS_JSON_URL" -o "$sdks_json"
sdk_file="$(SDK_VERSION="$SDK_VERSION" python3 - "$sdks_json" <<'PY'
import json, os, sys
wanted = os.environ.get("SDK_VERSION") or ""
sdks = json.load(open(sys.argv[1]))
match = [s for s in sdks if s["version"] == wanted] if wanted else sdks[-1:]
if not match:
    sys.exit(f"SDK {wanted} není v seznamu ({', '.join(s['version'] for s in sdks)})")
print(match[0]["linux"])
PY
)"
rm -f "$sdks_json"

if [ ! -x "$CIQ_HOME/sdk/bin/monkeyc" ]; then
    tmp_zip="$(mktemp --suffix=.zip)"
    curl -fL --progress-bar "$SDK_BASE_URL/$sdk_file" -o "$tmp_zip"
    mkdir -p "$CIQ_HOME/sdk"
    unzip -q -o "$tmp_zip" -d "$CIQ_HOME/sdk"
    rm -f "$tmp_zip"
fi
"$CIQ_HOME/sdk/bin/monkeyc" --version

log "Podepisovací klíč vývojáře"
mkdir -p "$CIQ_HOME/keys"
if [ ! -f "$CIQ_HOME/keys/developer_key.der" ]; then
    openssl genrsa -out "$CIQ_HOME/keys/developer_key.pem" 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in "$CIQ_HOME/keys/developer_key.pem" \
        -out "$CIQ_HOME/keys/developer_key.der" -nocrypt
    chmod 600 "$CIQ_HOME/keys/developer_key.pem" "$CIQ_HOME/keys/developer_key.der"
fi

log "connect-iq-sdk-manager (nahrazuje GUI SDK Manager, umí běžet bez obrazovky)"
if [ ! -x "$CIQ_HOME/bin/connect-iq-sdk-manager" ]; then
    curl -fsSL https://raw.githubusercontent.com/lindell/connect-iq-sdk-manager-cli/master/install.sh \
        | sh -s -- -b "$CIQ_HOME/bin" >/dev/null
fi

cat > "$CIQ_HOME/env.sh" <<EOF
# Načti přes: source $CIQ_HOME/env.sh
export CIQ_HOME="$CIQ_HOME"
export CIQ_SDK="\$CIQ_HOME/sdk"
export CIQ_DEVELOPER_KEY="\$CIQ_HOME/keys/developer_key.der"
export PATH="\$CIQ_SDK/bin:\$CIQ_HOME/bin:\$PATH"
export LD_LIBRARY_PATH="$WEBKIT_PREFIX/usr/lib/x86_64-linux-gnu\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF
log "Prostředí zapsáno do $CIQ_HOME/env.sh"

if [ -n "${GARMIN_USERNAME:-}" ] && [ -n "${GARMIN_PASSWORD:-}" ]; then
    log "Přihlášení k Garmin developer účtu a stažení device packů"
    export PATH="$CIQ_HOME/bin:$PATH"
    connect-iq-sdk-manager agreement accept
    connect-iq-sdk-manager login
    # Každý projekt má svůj seznam zařízení, takže se stahují oba manifesty -
    # jinak by chyběly Edge pro palubovku.
    for manifest in "$(dirname "$0")"/*/manifest.xml; do
        log "Zařízení podle $(basename "$(dirname "$manifest")")"
        connect-iq-sdk-manager device download --manifest "$manifest" --include-fonts
    done
    log "Stažená zařízení: $(ls "$HOME/.Garmin/ConnectIQ/Devices" 2>/dev/null | tr '\n' ' ')"
else
    cat <<'EOF'

==> Device packy přeskočeny
    Definice zařízení a fonty pro simulátor jsou u Garminu za přihlášením.
    Nastav proměnné a spusť skript znovu (nebo jen tuhle část):

        export GARMIN_USERNAME="..."
        export GARMIN_PASSWORD="..."
        source ~/connectiq/env.sh
        connect-iq-sdk-manager agreement accept
        connect-iq-sdk-manager login
        connect-iq-sdk-manager device download --manifest garmin/RideDashboard/manifest.xml --include-fonts
        connect-iq-sdk-manager device download --manifest garmin/QMailDashboard/manifest.xml --include-fonts

    Bez nich jde psát a verzovat kód, ale `monkeyc -d <zařízení>` ani simulátor
    se nespustí. Náhled dashboardu zatím vykreslí garmin/tools/preview.py.
EOF
fi

log "Hotovo"
