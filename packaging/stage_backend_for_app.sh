#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$ROOT_DIR/dist/procreate-to-tif-cli}"
STAGE_DIR="${STAGE_DIR:-$ROOT_DIR/macos-app/ProArchiveConverter/backend-bundle}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "error: Backend bundle directory not found: $SOURCE_DIR" >&2
  echo "hint: run packaging/build_backend_cli.sh first." >&2
  exit 1
fi

mkdir -p "$STAGE_DIR"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$SOURCE_DIR"/ "$STAGE_DIR"/
else
  rm -rf "$STAGE_DIR"/*
  cp -R "$SOURCE_DIR"/. "$STAGE_DIR"/
fi

echo "Staged backend bundle for app embedding."
echo "Source: $SOURCE_DIR"
echo "Stage:  $STAGE_DIR"
