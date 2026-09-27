#!/bin/bash
# SPT server helper. Installed as /usr/local/bin/spt.
set -euo pipefail
DIR=/opt/spt
cd "$DIR"

set_env() { sed -i "s|^$1=.*|$1=$2|" .env; }

case "${1:-help}" in
    start)    docker compose up -d --build ;;
    stop)     docker compose stop ;;
    restart)  docker compose restart spt ;;
    logs)     docker compose logs -f --tail "${2:-200}" spt ;;
    status)
        grep -E '^(SPT_VERSION|FIKA_VERSION)=' .env
        docker compose ps
        docker stats --no-stream spt 2>/dev/null || true ;;
    update)   # spt update <spt-version> [fika-version|none]
        [ -n "${2:-}" ] || { echo "usage: spt update <spt-version> [fika-version|none]"; exit 1; }
        set_env SPT_VERSION "$2"
        [ -n "${3:-}" ] && set_env FIKA_VERSION "$([ "$3" = none ] && echo '' || echo "$3")"
        docker compose up -d --build ;;
    fika)     # spt fika <version|none>
        [ -n "${2:-}" ] || { echo "usage: spt fika <version|none>"; exit 1; }
        if [ "$2" = none ]; then set_env FIKA_VERSION ""; rm -rf mods/fika-server
        else set_env FIKA_VERSION "$2"; fi
        docker compose up -d ;;
    mods)     ls -1 mods ;;
    backup)   # profiles + mod configs, without the heavy mod files
        mkdir -p backups
        f="backups/spt-$(date +%F_%H%M).tar.gz"
        tar -czf "$f" profiles config server/user/sptappdata server/user/credentials \
            $(find mods -path '*/config*' -maxdepth 3 -type d 2>/dev/null) mods/fika-server/assets/configs 2>/dev/null || true
        ls -lh "$f" ;;
    *)
        cat <<EOF
spt start                  build and start the server
spt stop | restart         stop / restart
spt logs [N]               follow logs
spt status                 versions, container state, RAM/CPU
spt update <ver> [fika]    switch SPT version (and optionally Fika; 'none' disables it)
spt fika <ver|none>        switch or disable Fika
spt mods                   list installed server mods
spt backup                 back up profiles and configs to /opt/spt/backups
EOF
        ;;
esac
