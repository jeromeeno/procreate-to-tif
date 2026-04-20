#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 /path/to/ProArchive\\ Converter.app [NOTARY_PROFILE]" >&2
  echo "example: $0 ./build/ProArchive\\ Converter.app AC_NOTARY_PROFILE" >&2
  exit 1
fi

APP_PATH="$1"
NOTARY_PROFILE="${2:-${NOTARY_PROFILE:-}}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "error: notary keychain profile missing." >&2
  echo "set NOTARY_PROFILE env var or provide it as the second argument." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun not found." >&2
  exit 1
fi

APP_PARENT="$(cd "$(dirname "$APP_PATH")" && pwd)"
APP_NAME="$(basename "$APP_PATH")"
ZIP_PATH="$APP_PARENT/${APP_NAME}.zip"

echo "[notary] Preparing archive: $ZIP_PATH"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "[notary] Submitting with profile: $NOTARY_PROFILE"
xcrun notarytool submit "$ZIP_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "[notary] Stapling ticket..."
xcrun stapler staple "$APP_PATH"

echo "[notary] Verifying staple..."
xcrun stapler validate "$APP_PATH"

echo "[notary] Done."
