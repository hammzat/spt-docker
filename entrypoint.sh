#!/bin/bash
# Installs the requested SPT / Fika versions into the server volume, then starts the server.
set -euo pipefail

SERVER=/opt/spt/server
MODS="$SERVER/user/mods"
CONFIG_OVERRIDES=/opt/spt/config
SPT_REPO="${SPT_REPO:-SP-Tushonka/build}"
FIKA_REPO="${FIKA_REPO:-project-fika/Fika-Server-CSharp}"
SPT_VERSION="${SPT_VERSION:?SPT_VERSION is not set (see .env)}"
FIKA_VERSION="${FIKA_VERSION:-}"
SPT_PORT="${SPT_PORT:-6969}"

log() { echo "[entrypoint] $*"; }

# First .7z/.zip asset URL of a GitHub release tag (tries "X" and "vX").
release_asset() {
    local repo=$1 tag=$2 ext=$3 url
    for t in "$tag" "v$tag"; do
        url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/tags/$t" 2>/dev/null \
            | jq -r --arg ext "$ext" '[.assets[] | select(.name | endswith($ext))][0].browser_download_url // empty') || true
        [ -n "$url" ] && { echo "$url"; return 0; }
    done
    return 1
}

install_spt() {
    log "Installing SPT $SPT_VERSION from $SPT_REPO"
    local url tmp runtime
    url=$(release_asset "$SPT_REPO" "$SPT_VERSION" .7z) \
        || { log "ERROR: release $SPT_VERSION not found in $SPT_REPO"; exit 1; }
    tmp=$(mktemp -d)
    curl -fsSL --retry 3 -o "$tmp/spt.7z" "$url"
    7z x -y -bso0 -bsp0 -o"$tmp/x" "$tmp/spt.7z"
    runtime=$(dirname "$(find "$tmp/x" -name SPT.Server.Linux.dll -print -quit)")
    [ -f "$runtime/SPT.Server.Linux.dll" ] || { log "ERROR: SPT.Server.Linux.dll not found in archive"; exit 1; }
    # Replace server files, keep user/ (profiles, mods, settings).
    rsync -a --delete --exclude=/user/ --exclude=/EscapeFromTarkov_Data/ "$runtime/" "$SERVER/"
    rsync -a --ignore-existing "$runtime/user/" "$SERVER/user/" 2>/dev/null || true
    echo "$SPT_VERSION" > "$SERVER/.spt-version"
    rm -rf "$tmp"
    log "SPT $SPT_VERSION installed"
}

install_fika() {
    log "Installing Fika $FIKA_VERSION from $FIKA_REPO"
    local url tmp src
    url=$(release_asset "$FIKA_REPO" "$FIKA_VERSION" .zip) \
        || { log "ERROR: Fika release $FIKA_VERSION not found in $FIKA_REPO"; exit 1; }
    tmp=$(mktemp -d)
    curl -fsSL --retry 3 -o "$tmp/fika.zip" "$url"
    unzip -q "$tmp/fika.zip" -d "$tmp/x"
    src=$(dirname "$(find "$tmp/x" -name FikaServer.dll -print -quit)")
    mkdir -p "$MODS/fika-server"
    # Keep the generated config between Fika updates.
    rsync -a --exclude=/assets/configs/ "$src/" "$MODS/fika-server/"
    echo "$FIKA_VERSION" > "$MODS/fika-server/.fika-version"
    rm -rf "$tmp"
    log "Fika $FIKA_VERSION installed"
}

mkdir -p "$MODS" "$SERVER/user/profiles"

if [ "$(cat "$SERVER/.spt-version" 2>/dev/null)" != "$SPT_VERSION" ]; then
    install_spt
fi

if [ -n "$FIKA_VERSION" ] && [ "$FIKA_VERSION" != "none" ]; then
    if [ "$(cat "$MODS/fika-server/.fika-version" 2>/dev/null)" != "$FIKA_VERSION" ]; then
        install_fika
    fi
elif [ -d "$MODS/fika-server" ]; then
    log "WARNING: FIKA_VERSION is empty but mods/fika-server exists — delete it to disable Fika"
fi

# Config overrides: ./config/*.json replace files in SPT_Data/configs on every start.
if compgen -G "$CONFIG_OVERRIDES/*.json" > /dev/null; then
    for f in "$CONFIG_OVERRIDES"/*.json; do
        log "Config override: $(basename "$f")"
        cp "$f" "$SERVER/SPT_Data/configs/"
    done
fi

# Listen on all interfaces inside the container and advertise the public address.
HTTP_CFG="$SERVER/SPT_Data/configs/http.json"
SPT_BACKEND_PORT="${SPT_BACKEND_PORT:-$SPT_PORT}"
jq --arg ip "${SPT_BACKEND_IP:?SPT_BACKEND_IP is not set}" --argjson port "$SPT_PORT" --argjson bport "$SPT_BACKEND_PORT" \
    '.ip = "0.0.0.0" | .port = $port | .backendIp = $ip | .backendPort = $bport' \
    "$HTTP_CFG" > "$HTTP_CFG.tmp" && mv "$HTTP_CFG.tmp" "$HTTP_CFG"

# Fika overrides SPT's http settings with its own copy, so keep it in sync.
FIKA_CFG="$MODS/fika-server/assets/configs/fika.jsonc"
if [ -f "$FIKA_CFG" ]; then
    if jq --arg ip "$SPT_BACKEND_IP" --argjson port "$SPT_PORT" --argjson bport "$SPT_BACKEND_PORT" \
        '.server.SPT.http = {ip: "0.0.0.0", port: $port, backendIp: $ip, backendPort: $bport}' \
        "$FIKA_CFG" > "$FIKA_CFG.tmp" 2>/dev/null; then
        mv "$FIKA_CFG.tmp" "$FIKA_CFG"
    else
        rm -f "$FIKA_CFG.tmp"
        log "WARNING: could not update $FIKA_CFG (comments in JSONC?) — set server.SPT.http by hand"
    fi
fi

log "Starting SPT $SPT_VERSION (Fika: ${FIKA_VERSION:-off}), backend $SPT_BACKEND_IP:$SPT_BACKEND_PORT"
cd "$SERVER"
exec dotnet SPT.Server.Linux.dll
