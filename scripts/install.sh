#!/bin/zsh

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_ROOT="${DEX_INSTALL_DIR:-$HOME/Applications}"
TARGET="$INSTALL_ROOT/Dex.app"

running_dex_processes() {
    ps -axo pid=,command= | awk \
        -v installed="$TARGET/Contents/MacOS/Dex" \
        -v packaged="$ROOT/build/Dex.app/Contents/MacOS/Dex" \
        -v development="$ROOT/.build/" '
        $2 == installed || $2 == packaged || (index($2, development) == 1 && $2 ~ /\/Dex$/) {
            print $1
        }
    '
}

stop_running_dex() {
    local running_pids
    running_pids="$(running_dex_processes)"
    [[ -z "$running_pids" ]] && return

    for pid in ${(f)running_pids}; do
        kill "$pid" 2>/dev/null || true
    done

    for _ in {1..50}; do
        [[ -z "$(running_dex_processes)" ]] && return
        sleep 0.1
    done

    echo "Could not stop the existing Dex process. Quit Dex and run the installer again." >&2
    exit 1
}

"$ROOT/scripts/build-app.sh" release

stop_running_dex
mkdir -p "$INSTALL_ROOT"
rm -rf "$TARGET"
ditto "$ROOT/build/Dex.app" "$TARGET"

open "$TARGET"

echo "Installed Dex at $TARGET"
