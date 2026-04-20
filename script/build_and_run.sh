#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/macos-app/ProArchiveConverter"
DIST_DIR="$ROOT_DIR/dist"
APP_DISPLAY_NAME="ProArchive Converter"
APP_EXECUTABLE_NAME="ProArchiveConverterApp"
BUNDLE_ID="xyz.ateli3r.proarchiveconverter"
MIN_SYSTEM_VERSION="13.0"

APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS_DIR="$APP_CONTENTS/MacOS"
APP_RESOURCES_DIR="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS_DIR/$APP_EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="ProArchiveConverter_ProArchiveConverterApp.bundle"
BACKEND_STAGE_DIR="$PACKAGE_DIR/backend-bundle"
ICON_SOURCE_PNG="$PACKAGE_DIR/Sources/ProArchiveConverterApp/Resources/branding/stylusflame.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICNS_PATH="$APP_RESOURCES_DIR/AppIcon.icns"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
}

kill_existing() {
  /usr/bin/pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
}

build_app() {
  mkdir -p "$DIST_DIR"
  /usr/bin/swift build --package-path "$PACKAGE_DIR"

  local build_bin_dir
  build_bin_dir="$(
    cd "$PACKAGE_DIR"
    /usr/bin/swift build --show-bin-path
  )"
  local built_binary="$build_bin_dir/$APP_EXECUTABLE_NAME"
  local built_resource_bundle="$build_bin_dir/$RESOURCE_BUNDLE_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS_DIR" "$APP_RESOURCES_DIR"
  cp "$built_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  if [[ -d "$built_resource_bundle" ]]; then
    cp -R "$built_resource_bundle" "$APP_RESOURCES_DIR/$RESOURCE_BUNDLE_NAME"
  fi

  if [[ -d "$BACKEND_STAGE_DIR" ]]; then
    mkdir -p "$APP_RESOURCES_DIR/backend"
    cp -R "$BACKEND_STAGE_DIR"/. "$APP_RESOURCES_DIR/backend/"
  fi

  create_app_icon
  write_info_plist
}

create_app_icon() {
  if [[ ! -f "$ICON_SOURCE_PNG" ]]; then
    return
  fi
  if ! command -v /usr/bin/sips >/dev/null 2>&1 || ! command -v /usr/bin/iconutil >/dev/null 2>&1; then
    return
  fi

  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  /usr/bin/sips -z 16 16 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  /usr/bin/sips -z 32 32 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  /usr/bin/sips -z 32 32 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  /usr/bin/sips -z 64 64 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  /usr/bin/sips -z 128 128 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  /usr/bin/sips -z 256 256 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  /usr/bin/sips -z 256 256 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  /usr/bin/sips -z 512 512 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  /usr/bin/sips -z 512 512 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  /usr/bin/sips -z 1024 1024 "$ICON_SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

kill_existing
build_app

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    /usr/bin/pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null
    ;;
  *)
    usage
    exit 2
    ;;
esac
