#!/bin/zsh

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dex-icons.XXXXXX")"

trap 'rm -rf "$WORK_DIR"' EXIT

generate_icon() {
  local source="$1"
  local output="$2"
  local name="${output:t:r}"
  local iconset="$WORK_DIR/$name.iconset"
  local master="$WORK_DIR/$name.png"
  local rendered="$WORK_DIR/$name-rendered.png"

  mkdir -p "$iconset"
  xcrun swift "$ROOT/scripts/render-svg.swift" "$source" "$rendered" 1024
  sips -z 1024 1024 "$rendered" --out "$master" >/dev/null

  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$master" \
      --out "$iconset/icon_${size}x${size}.png" >/dev/null

    local retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$master" \
      --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$iconset" -o "$output"
  echo "$output"
}

generate_icon "$ROOT/Resources/DexAppIcon.svg" "$ROOT/Resources/Dex.icns"
