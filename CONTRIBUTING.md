# Contributing

Thanks for taking an interest in `procreate-to-tif`.

## Development Setup

The Python CLI targets Python 3.9+ and is intended to be cross-platform.

On macOS, install the LZO system library first:

```bash
brew install lzo
```

On Debian/Ubuntu:

```bash
sudo apt-get install -y liblzo2-dev ffmpeg
```

On Fedora:

```bash
sudo dnf install -y lzo-devel ffmpeg
```

Then create a virtual environment and install the project in editable mode with
developer dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -e ".[dev]"
```

## Running Tests

Run the Python test suite:

```bash
pytest -q
```

Build the Python package artifacts:

```bash
python -m build
```

Run the macOS bridge tests:

```bash
swift test --package-path macos-app/ProArchiveConverter
```

## Notes

- Python CLI checks run in CI on both Ubuntu and macOS.
- The SwiftUI app test job runs separately on macOS only.
- The repo does not ship personal `.procreate` artwork files for tests.
- Smoke tests generate a minimal synthetic `.procreate` archive at runtime.
- `requirements.txt` is kept for simple runtime installs, but contributor setup
  should prefer `pip install -e ".[dev]"`.
- The Linux CLI backlog lives in `LINUX_CLI_BACKLOG.local.md` and is
  intentionally git-ignored.
