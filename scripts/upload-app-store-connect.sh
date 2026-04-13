#!/usr/bin/env bash
# Upload the exported IPA to App Store Connect.
# Prerequisite: run scripts/archive-for-testflight.sh first.
#
# Use ONE of these auth methods:
#
# --- Method 1: App Store Connect API key (JWT) ---
#   APP_STORE_CONNECT_ISSUER_ID
#   APP_STORE_CONNECT_KEY_ID
#   APP_STORE_CONNECT_API_KEY_PATH  OR  ./private_keys/AuthKey_<KEY_ID>.p8
#
# --- Method 2: Apple ID + app-specific password (no .p8 file) ---
#   ASC_APPLE_ID                    — your Apple ID email
#   ASC_APP_SPECIFIC_PASSWORD       — 16-char app-specific password from appleid.apple.com
#   ASC_PROVIDER_PUBLIC_ID        — Provider ID (UUID); see below
#
# Provider ID: App Store Connect → top-left team name / account menu often shows it, or run:
#   xcrun altool --list-providers -u 'you@email.com' --app-password 'xxxx-xxxx-xxxx-xxxx'
# (Use the "Provider" / Team ID row that matches your app’s team.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
IPA="$ROOT/build/export/ScribbleTale.ipa"
if [[ ! -f "$IPA" ]]; then
  echo "Missing $IPA — run scripts/archive-for-testflight.sh first."
  exit 1
fi

use_jwt=false
use_apple_id=false

if [[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] && [[ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]]; then
  P8="${APP_STORE_CONNECT_API_KEY_PATH:-}"
  if [[ -z "$P8" ]]; then
    P8="$ROOT/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
  fi
  if [[ -f "$P8" ]]; then
    use_jwt=true
  fi
fi

if [[ -n "${ASC_APPLE_ID:-}" ]] && [[ -n "${ASC_APP_SPECIFIC_PASSWORD:-}" ]] && [[ -n "${ASC_PROVIDER_PUBLIC_ID:-}" ]]; then
  use_apple_id=true
fi

if [[ "$use_jwt" == true ]]; then
  exec xcrun altool --upload-package "$IPA" \
    --api-key "$APP_STORE_CONNECT_KEY_ID" \
    --api-issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --p8-file-path "$P8" \
    -t ios \
    --show-progress
fi

if [[ "$use_apple_id" == true ]]; then
  exec xcrun altool --upload-package "$IPA" \
    --username "$ASC_APPLE_ID" \
    --app-password "$ASC_APP_SPECIFIC_PASSWORD" \
    --provider-public-id "$ASC_PROVIDER_PUBLIC_ID" \
    -t ios \
    --show-progress
fi

echo "No working authentication found."
echo ""
echo "If you lost the API key .p8 file, Apple cannot give you another copy — create a NEW key in"
echo "App Store Connect → Users and Access → Integrations → Keys, download the .p8 once, then either:"
echo "  • Put it at: private_keys/AuthKey_<KEY_ID>.p8 and set ISSUER_ID + KEY_ID, or"
echo "  • Use Method 2 (no .p8): set ASC_APPLE_ID, ASC_APP_SPECIFIC_PASSWORD, ASC_PROVIDER_PUBLIC_ID"
echo ""
echo "Create an app-specific password: https://appleid.apple.com → Sign-In and Security → App-Specific Passwords"
exit 1
