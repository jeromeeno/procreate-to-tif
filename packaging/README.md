# Backend Packaging

This folder contains scripts for building a bundled Python backend CLI for the macOS app.
These scripts are for the macOS app only; Linux users should run the CLI
directly rather than using this packaging flow.

## Build Bundled CLI

```bash
./packaging/build_backend_cli.sh
```

Output:

- Bundle directory: `dist/procreate-to-tif-cli/`
- Executable: `dist/procreate-to-tif-cli/procreate-to-tif-cli`

The build uses PyInstaller in `onedir` mode via `packaging/pyinstaller/proarchive_cli.spec`.

## Optional Environment Overrides

- `PYTHON_BIN`: Python interpreter used for PyInstaller (default: `.venv/bin/python`)
- `PROARCHIVE_FFMPEG_BIN`: Explicit ffmpeg binary to bundle (otherwise uses `ffmpeg` from `PATH`)
- `PROARCHIVE_LZO_LIB`: Explicit `liblzo*.dylib` path to bundle

## Stage For App Embedding

```bash
./packaging/stage_backend_for_app.sh
```

Default staging destination:

- `macos-app/ProArchiveConverter/backend-bundle/`

The SwiftUI app auto-detects this staged executable for local development.

## Sign And Notarize (Distribution)

Sign an exported `.app` bundle:

```bash
./packaging/sign_app_bundle.sh "/path/to/ProArchive Converter.app" "Developer ID Application: Your Name (TEAMID)"
```

Notarize and staple (requires a configured `notarytool` keychain profile):

```bash
./packaging/notarize_app.sh "/path/to/ProArchive Converter.app" "AC_NOTARY_PROFILE"
```

Notes:

- Sign nested binaries first, then the top-level app bundle.
- Notarization requires Apple Developer credentials and a valid Team ID.
