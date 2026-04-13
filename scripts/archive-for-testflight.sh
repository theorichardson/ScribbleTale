#!/usr/bin/env bash
# Archive Release, export, and upload to App Store Connect (TestFlight pipeline).
#
# ExportOptions.plist must include destination = upload (see repo root). Upload uses the
# same Apple ID / team session as Xcode (Accounts in Settings) — no separate API key file.
#
# For IPA on disk only (no upload), use ExportOptions-local-export.plist instead:
#   xcodebuild -exportArchive ... -exportOptionsPlist ExportOptions-local-export.plist
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p build
echo "Archiving…"
xcodebuild -project ScribbleTale.xcodeproj -scheme ScribbleTale -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/ScribbleTale.xcarchive archive
echo "Exporting and uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath build/ScribbleTale.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
echo "Done. If upload succeeded, check App Store Connect → TestFlight (processing can take several minutes)."
echo "Archive: $ROOT/build/ScribbleTale.xcarchive"
