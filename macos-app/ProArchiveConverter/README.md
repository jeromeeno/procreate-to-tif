# ProArchive Converter (SwiftUI macOS Companion App)

This folder contains a Swift Package with:

- `ProcreateBridgeCore`: process bridge + JSONL event decoder for the Python CLI
- `ProArchiveConverterApp`: SwiftUI macOS app that runs the CLI and shows progress/logs

## Run Locally

```bash
cd ../..
./packaging/build_backend_cli.sh
./packaging/stage_backend_for_app.sh
./script/build_and_run.sh
```

This builds the Swift package, stages a real local app bundle in
`dist/ProArchive Converter.app`, and launches that bundle. Running the raw
SwiftPM executable with `swift run` is still possible for debugging, but macOS
will often show the generic `exec` icon because it is not a real `.app` bundle.
The backend build and staging steps are required for the GUI to perform real
conversions out of the box.

## Configure Backend Path

At runtime, the app expects a CLI executable that matches your Python converter flags.

Preferred options:

- Bundled app resource named `procreate-to-tif-cli`
- Environment variable `PROARCHIVE_CLI_PATH=/absolute/path/to/cli` (legacy `PROCREATE_CLI_PATH` also works)
- Manual selection from the UI

## Test Bridge Layer

```bash
cd macos-app/ProArchiveConverter
swift test
```

## Log Autosave

The app now autosaves Event Log lines to:

- `~/Library/Logs/ProArchiveConverter`

Each app launch writes to a new timestamped `session-*.log` file. You can open this folder from the app via `Event Log > Open Log Folder`.
