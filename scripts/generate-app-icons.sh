#!/usr/bin/env bash
# Generate App Store icon PNGs from 1024×1024 master (sips).
set -euo pipefail
ICONSET="$(cd "$(dirname "$0")/.." && pwd)/ScribbleTale/Resources/Assets.xcassets/AppIcon.appiconset"
SRC="${ICONSET}/AppIcon-1024.png"
if [[ ! -f "$SRC" ]]; then
  echo "Missing $SRC — create it first (e.g. swift scripts/generate-placeholder-app-icon.swift)" >&2
  exit 1
fi
W=$(sips -g pixelWidth "$SRC" 2>/dev/null | awk '/pixelWidth/ {print $2}')
H=$(sips -g pixelHeight "$SRC" 2>/dev/null | awk '/pixelHeight/ {print $2}')
if [[ "$W" != "1024" || "$H" != "1024" ]]; then
  echo "AppIcon-1024.png must be exactly 1024×1024 for App Store (got ${W}×${H}). Fix: sips -z 1024 1024 \"$SRC\"" >&2
  exit 1
fi

resize() {
  local out="$1" px="$2"
  sips -z "$px" "$px" "$SRC" --out "$ICONSET/$out" >/dev/null
}

cd "$ICONSET"
resize "Icon-20@2x.png" 40
resize "Icon-20@3x.png" 60
resize "Icon-29@2x.png" 58
resize "Icon-29@3x.png" 87
resize "Icon-40@2x.png" 80
resize "Icon-40@3x.png" 120
resize "Icon-60@3x.png" 180
resize "Icon-20.png" 20
resize "Icon-29.png" 29
resize "Icon-40.png" 40
resize "Icon-76.png" 76
resize "Icon-76@2x.png" 152
resize "Icon-83.5@2x.png" 167

echo "Wrote icons to $ICONSET"
