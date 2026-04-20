#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

repo_root = Path(__file__).resolve().parent
src_dir = repo_root / "src"
if str(src_dir) not in sys.path:
    sys.path.insert(0, str(src_dir))

from procreate_to_tif.cli import main


if __name__ == "__main__":
    raise SystemExit(main())

