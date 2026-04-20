# Procreate to TIF/PSD Converter Manual

## Overview
This tool converts `.procreate` archives into multiple export formats:

- Layered PSD
- Flat PNG
- Flat JPG
- Animated WebP (when animation metadata indicates animation)
- Animated GIF (when animation metadata indicates animation)
- Stitched timelapse MP4 from `video/segments/segment-*.mp4`

By default, outputs are written to `./exports`.
The Python CLI is cross-platform; the SwiftUI companion app is macOS-only.

## Requirements

### Python
- Python 3.9+

### Python packages
Installed from `requirements.txt`:
- `python-lzo`
- `lz4`
- `Pillow`
- `numpy`
- `pytoshop`
- `six`

### System dependencies
- LZO library (required by `python-lzo`)
  - macOS: `brew install lzo`
- `ffmpeg` (required for multi-segment timelapse MP4 stitching)

Suggested Linux packages:

- Debian/Ubuntu: `liblzo2-dev` and `ffmpeg`
- Fedora: `lzo-devel` and `ffmpeg`

## Installation
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

If you plan to run the tests or work on the project, install the developer
extras instead:

```bash
pip install -e ".[dev]"
```

## Entry Points
- `python convert.py ...`
- `python -m procreate_to_tif ...`
- `procreate-to-tif ...` (if installed via package script)

## Basic Usage

### PSD only (default)
```bash
python convert.py "MyArtwork.procreate"
```

### PSD + flat PNG + flat JPG
```bash
python convert.py --flat-png --flat-jpg "MyArtwork.procreate"
```

### Animated outputs
```bash
python convert.py --animated-webp --animated-gif "AnimatedArtwork.procreate"
```

### Timelapse MP4 stitching
```bash
python convert.py --timelapse-mp4 "MyArtwork.procreate"
```

### Flat outputs only (no PSD)
```bash
python convert.py --no-psd --flat-png --flat-jpg "MyArtwork.procreate"
```

### Batch
```bash
python convert.py --flat-png --flat-jpg --animated-webp --animated-gif --timelapse-mp4 FilesToConvert/*.procreate
```

## Linux Notes

- The CLI runs on Linux once `python-lzo`, `lz4`, and `ffmpeg` are installed.
- The macOS-specific `compression_tool` and `/usr/lib/libcompression.dylib`
  fallback are optional and only used when present.
- The editable install and test path is verified in Ubuntu CI with
  `pip install -e ".[dev]"` and `pytest -q`.
- The macOS GUI and packaging steps in this manual do not apply on Linux.

## CLI Reference

```text
usage: convert.py [-h] [--outdir OUTDIR] [--no-psd] [--flat-png] [--flat-jpg]
                  [--animated-webp] [--animated-gif] [--timelapse-mp4]
                  [--jpg-quality JPG_QUALITY] [--apply-mask]
                  [--no-unpremultiply] [--no-background]
                  [--log-format {text,jsonl}]
                  files [files ...]
```

### Positional
- `files`:
  - One or more `.procreate` files
  - Glob patterns are supported (example: `*.procreate`)

### Options
- `--outdir OUTDIR`
  - Output directory
  - Default: `./exports`

- `--no-psd`
  - Disable layered PSD export

- `--flat-png`
  - Export flat PNG

- `--flat-jpg`
  - Export flat JPG

- `--animated-webp`
  - Export animated WebP when file is detected animated

- `--animated-gif`
  - Export animated GIF when file is detected animated

- `--timelapse-mp4`
  - Stitch timelapse replay segments to MP4 when segments exist in archive

- `--jpg-quality JPG_QUALITY`
  - JPG quality from 1 to 100
  - Default: `95`

- `--apply-mask`
  - Apply Procreate document mask to exports
  - Off by default

- `--no-unpremultiply`
  - Skip alpha un-premultiplication

- `--no-background`
  - Do not add Procreate document background color as bottom PSD layer

- `--log-format {text,jsonl}`
  - Console log format
  - `text` (default): human-readable logs
  - `jsonl`: one JSON object per line for machine parsing

## Output Formats and Behavior

### 1) Layered PSD
- Preserves layer names when present
- Preserves visibility, opacity, and supported blend modes
- Adds `Background Color` as bottom PSD layer by default (unless `--no-background`)
- Writes merged composite image into PSD image data (improves preview compatibility)
- Embeds ICC profile when available
- Uses Photoshop-safe RAW channel compression
- Crops each layer to alpha bounds to reduce size while keeping layer positions

#### Blend mode mapping
- `0` -> Normal
- `1` -> Multiply
- `2` -> Screen
- `3` -> Overlay
- `8` -> Darken
- `9` -> Lighten
- `17` -> Color Dodge
- `18` -> Color Burn
- Unknown values fall back to Normal

### 2) Flat PNG
- RGBA output
- Uses reconstructed Procreate composite when available, otherwise layer flatten fallback
- Preserves transparency where applicable
- Includes DPI and ICC profile when available

### 3) Flat JPG
- RGB output
- Alpha is composited onto a matte color:
  - Procreate background color if available
  - Otherwise white
- Includes DPI and ICC profile when available

### 4) Animated WebP / GIF
- Exported only when animation is detected
- Frame source is Procreate content layers
- Honors sticky animation flags:
  - `isLastItemAnimationBackground`: last frame item is always-on background
  - `isFirstItemAnimationForeground`: first frame item is always-on foreground
- Playback behavior:
  - `playbackDirection == 1` reverses frame order
  - `playbackMode == 2` uses ping-pong sequence
- Frame durations from `frameRate` and `animationHeldLength`
- If requested but not animated, export is skipped with info log

### 5) Timelapse MP4
- Reads `video/segments/segment-*.mp4` from archive
- Sorts segments by numeric segment index
- Stitch strategy:
  1. `ffmpeg` concat with `-c copy`
  2. Fallback transcode (`libx264` + `aac`) if copy fails
- If one segment exists, copies directly
- If no segments exist, skipped with info log

## How Files Are Interpreted

### Archive internals used
- `Document.archive` (binary plist metadata)
- `QuickLook/Thumbnail.png` (preview asset, not currently exported directly)
- `video/segments/segment-*.mp4` (timelapse replay)
- `<UUID>/*.chunk` (LZO-compressed tile data for layers/composite/mask)

### Document metadata currently parsed
- Canvas dimensions and tile size
- DPI
- Orientation and horizontal/vertical flips
- ICC profile
- Background color and background visibility
- Content layers (`UUID`, name, opacity, hidden, blend, clipped)
- Composite UUID
- Mask UUID
- Animation settings:
  - `animationMode`
  - `playbackMode`
  - `playbackDirection`
  - `frameRate`
  - sticky flags
  - per-layer `animationHeldLength`

## Image Reconstruction Details
- Chunk data is LZO-decompressed
- Supports both 4-channel RGBA and 1-channel mask chunks
- Tiles are vertically flipped during reconstruction to match Procreate storage
- Orientation and flip metadata are applied post-reconstruction
- Un-premultiplication is applied by default to improve edge correctness in exports

## Mask Handling
- Disabled by default
- Enabled via `--apply-mask`
- Mask is ignored when empty or uniform (fully transparent or fully opaque)
- When used, mask alpha multiplies image alpha

## Output Location and Naming
- Default output directory: `./exports`
- Override with `--outdir`
- File names:
  - `name.psd`
  - `name.png`
  - `name.jpg`
  - `name.webp`
  - `name.gif`
  - `name.timelapse.mp4`

Note: if multiple inputs share the same base filename and same output directory, later conversions overwrite earlier outputs.

## Logging and Exit Codes
- Per file logs show conversion start and each produced output path
- Animated/video outputs show explicit skip messages when not applicable
- Missing input files are reported as `[ERROR]`
- Process exits `0` when all files succeed, `1` if any file fails
- `--log-format jsonl` emits events:
  - `run_start`: includes `total`
  - `file_start`: includes `file`, `index`, `total`
  - `file_success`: includes `file`, `index`, `total`, `width`, `height`, `layer_count`, `outputs`, optional `skipped`
  - `file_error`: includes `file`, `index`, `total`, `message`, `error_code`
  - `run_complete`: includes `total`, `successes`, `failures`

## SwiftUI Companion App

A native macOS SwiftUI companion app is included at:

- `macos-app/ProArchiveConverter`

The Swift package contains:

- `ProcreateBridgeCore`: CLI argument builder, JSONL event decoder, and process runner
- `ProArchiveConverterApp`: SwiftUI app with file selection, option toggles, progress, and log view

Run locally:

```bash
cd macos-app/ProArchiveConverter
swift run ProArchiveConverterApp
```

Bridge tests:

```bash
cd macos-app/ProArchiveConverter
swift test
```

## Backend Packaging (PyInstaller)

Build a bundled CLI for embedding into the macOS app:

```bash
./packaging/build_backend_cli.sh
```

This produces:

- `dist/procreate-to-tif-cli/`
- `dist/procreate-to-tif-cli/procreate-to-tif-cli`

Stage it into the app workspace:

```bash
./packaging/stage_backend_for_app.sh
```

Default stage path:

- `macos-app/ProArchiveConverter/backend-bundle/`

Optional build env vars:

- `PYTHON_BIN` (default `.venv/bin/python`)
- `PROARCHIVE_FFMPEG_BIN` (explicit ffmpeg binary to bundle)
- `PROARCHIVE_LZO_LIB` (explicit `liblzo*.dylib` to bundle)

Sign app bundle:

```bash
./packaging/sign_app_bundle.sh "/path/to/ProArchive Converter.app" "Developer ID Application: Your Name (TEAMID)"
```

Notarize and staple:

```bash
./packaging/notarize_app.sh "/path/to/ProArchive Converter.app" "AC_NOTARY_PROFILE"
```

## Known Limitations
- Layered TIFF is not implemented
- Only a subset of Procreate blend modes is mapped
- Advanced per-frame timing beyond `animationHeldLength` is not currently used
- Animated export loop/playback mapping is best-effort based on observed metadata

## Troubleshooting

### `python-lzo` install fails
- Ensure system LZO library is installed (`brew install lzo` on macOS)

### Timelapse MP4 not produced
- Ensure archive contains `video/segments/*.mp4`
- Ensure `ffmpeg` is installed and in `PATH`, or set `PROARCHIVE_FFMPEG_BIN`
- In bundled builds, place ffmpeg at `bin/ffmpeg` next to the backend CLI

### Animated outputs skipped
- File likely not detected as animated by metadata rules
- Check with `--animated-webp` / `--animated-gif` logs

### PSD opens but looks different than Procreate
- Could be due to unsupported blend modes or app-specific rendering differences
- Try flat PNG/JPG for appearance match and PSD for editability
