#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC_FILE="$ROOT_DIR/packaging/pyinstaller/proarchive_cli.spec"
PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/packaging/.build/pyinstaller}"
CLI_DIR="$DIST_DIR/procreate-to-tif-cli"
CLI_BIN="$CLI_DIR/procreate-to-tif-cli"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "error: Python interpreter not found or not executable: $PYTHON_BIN" >&2
  echo "hint: create venv first (python3 -m venv .venv) or set PYTHON_BIN." >&2
  exit 1
fi

if [[ ! -f "$SPEC_FILE" ]]; then
  echo "error: PyInstaller spec file not found: $SPEC_FILE" >&2
  exit 1
fi

echo "[build] Using Python: $PYTHON_BIN"

if ! "$PYTHON_BIN" -c "import PyInstaller" >/dev/null 2>&1; then
  echo "[build] Installing PyInstaller into current environment..."
  "$PYTHON_BIN" -m pip install --upgrade pyinstaller
fi

echo "[build] Building bundled backend CLI with PyInstaller..."
"$PYTHON_BIN" -m PyInstaller \
  --noconfirm \
  --clean \
  --workpath "$WORK_DIR" \
  --distpath "$DIST_DIR" \
  "$SPEC_FILE"

if [[ ! -x "$CLI_BIN" ]]; then
  echo "error: Expected output binary not found: $CLI_BIN" >&2
  exit 1
fi

echo "[build] Verifying executable..."
"$CLI_BIN" --help >/dev/null

echo
echo "Backend CLI build complete."
echo "Bundle directory: $CLI_DIR"
echo "Executable:       $CLI_BIN"
if [[ -x "$CLI_DIR/_internal/bin/ffmpeg" ]]; then
  echo "Bundled ffmpeg:   $CLI_DIR/_internal/bin/ffmpeg"
elif [[ -x "$CLI_DIR/bin/ffmpeg" ]]; then
  echo "Bundled ffmpeg:   $CLI_DIR/bin/ffmpeg"
else
  echo "Bundled ffmpeg:   (not found - set PROARCHIVE_FFMPEG_BIN before build if needed)"
fi
