#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 /path/to/ProArchive\\ Converter.app [SIGN_IDENTITY]" >&2
  echo "example: $0 ./build/ProArchive\\ Converter.app \"Developer ID Application: Your Name (TEAMID)\"" >&2
  exit 1
fi

APP_PATH="$1"
SIGN_IDENTITY="${2:-${SIGN_IDENTITY:-}}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "error: code-sign identity missing." >&2
  echo "set SIGN_IDENTITY env var or provide it as the second argument." >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 1
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo "error: codesign not found." >&2
  exit 1
fi

echo "[sign] App bundle: $APP_PATH"
echo "[sign] Identity:   $SIGN_IDENTITY"

sign_macho_file() {
  local target="$1"
  if file "$target" | grep -q "Mach-O"; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$target"
  fi
}

# Sign nested executables and dylibs first (backend + frameworks/resources).
while IFS= read -r -d '' file_path; do
  sign_macho_file "$file_path"
done < <(
  find "$APP_PATH/Contents" -type f \( \
    -name "*.dylib" -o \
    -name "*.so" -o \
    -perm -u+x \
  \) -print0
)

# Sign app frameworks and plug-ins directories if present.
for dir in \
  "$APP_PATH/Contents/Frameworks" \
  "$APP_PATH/Contents/PlugIns" \
  "$APP_PATH/Contents/XPCServices"; do
  if [[ -d "$dir" ]]; then
    while IFS= read -r -d '' nested_bundle; do
      codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$nested_bundle"
    done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print0)
  fi
done

# Sign the top-level app bundle last.
codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$APP_PATH"

echo "[sign] Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

echo "[sign] Done."
