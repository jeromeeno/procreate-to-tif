# Contributing

Thanks for taking an interest in `procreate-to-tif`.

## Development Setup

The Python CLI targets Python 3.9+.

On macOS, install the LZO system library first:

```bash
brew install lzo
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

- The repo does not ship personal `.procreate` artwork files for tests.
- Smoke tests generate a minimal synthetic `.procreate` archive at runtime.
- `requirements.txt` is kept for simple runtime installs, but contributor setup
  should prefer `pip install -e ".[dev]"`.
