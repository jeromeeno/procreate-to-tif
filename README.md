# procreate-to-tif v 0.1.0

  <img src="logo-assets/stylusflame.svg" alt="procreate-to-tif logo" width="180" align=left>
Convert `.procreate` archive files into layered Photoshop PSDs, flat PNG/JPG renders, optional animated WebP/GIF exports, and stitched timelapse MP4s.

This project is useful when you want to batch-convert Procreate archives on a Mac without manually opening each file on an iPad.

<p />



## Features

- Preserves layer names, visibility, opacity, and common blend modes in PSD output.
- Adds the Procreate background color as a bottom PSD layer by default.
- Exports flat PNG and JPG renders.
- Exports animated WebP and GIF when Procreate animation metadata is present.
- Stitches timelapse replay segments to MP4 when `video/segments/*.mp4` exists.
- Applies document orientation and flip metadata.
- Supports machine-readable JSON Lines logs for app integrations.

## Installation

`python-lzo` depends on the native LZO library. On macOS:

```bash
brew install lzo
```

For normal CLI use:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -e .
```

For contributor setup, install the developer extras instead:

```bash
pip install -e ".[dev]"
```

## Usage

The installed entry point is `procreate-to-tif`. The repository also includes
`convert.py` as a convenience wrapper for local checkouts.

```bash
# Layered PSD only
procreate-to-tif "MyArtwork.procreate"

# Layered PSD + flat PNG + flat JPG
procreate-to-tif --flat-png --flat-jpg "MyArtwork.procreate"

# Animated exports when animation metadata is enabled
procreate-to-tif --animated-webp --animated-gif "AnimatedArtwork.procreate"

# Stitch timelapse replay segments from archive to MP4
procreate-to-tif --timelapse-mp4 "MyArtwork.procreate"

# Flat PNG/JPG only (no PSD)
procreate-to-tif --no-psd --flat-png --flat-jpg "MyArtwork.procreate"

# Batch with glob
procreate-to-tif --outdir ./exports *.procreate

# Machine-readable progress/events for app integration
procreate-to-tif --log-format jsonl *.procreate
```

## Development

Run the Python test suite:

```bash
pytest -q
```

Build distributable artifacts:

```bash
python -m build
```

The test suite does not rely on checked-in personal artwork. Smoke tests create
a minimal synthetic `.procreate` archive at runtime so a fresh clone can run
cleanly in CI.

Contributor notes live in [CONTRIBUTING.md](CONTRIBUTING.md), and the more
detailed converter reference lives in [MANUAL.md](MANUAL.md).

## Optional macOS App

An included SwiftUI macOS companion app and process bridge live in
`macos-app/ProArchiveConverter`.

```bash
./packaging/build_backend_cli.sh
./packaging/stage_backend_for_app.sh
./script/build_and_run.sh
```

This launcher stages a real local `.app` bundle in `dist/ProArchive Converter.app`,
so the app opens with proper bundle metadata and icon instead of the generic
`exec` icon you get from running the raw SwiftPM executable directly. The first
two commands build and stage the Python backend that the GUI uses for actual
conversion work.

## Support

procreate-to-tif was made with love by Jerome Eno at Atelier Trois Rivieres, a
creative technology studio in Pittsburgh, PA. If procreate-to-tif saves you
time, you can support future updates on [Venmo](https://account.venmo.com/u/jerome-eno).

View Jerome's portfolio at [ATELI3R.](https://ateli3r.xyz)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
