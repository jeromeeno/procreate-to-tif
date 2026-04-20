# -*- mode: python ; coding: utf-8 -*-
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path


spec_dir = Path(globals().get("SPECPATH", Path.cwd())).resolve()
project_root = spec_dir.parents[1]
script_path = project_root / "convert.py"


def _first_existing(paths: list[Path]) -> Path | None:
    for path in paths:
        if path.exists():
            return path
    return None


def _resolve_ffmpeg_binary() -> Path | None:
    env_bin = os.environ.get("PROARCHIVE_FFMPEG_BIN")
    if env_bin:
        path = Path(env_bin).expanduser()
        if path.exists():
            return path

    discovered = shutil.which("ffmpeg")
    if discovered:
        return Path(discovered)
    return None


def _resolve_lzo_library_candidates() -> list[Path]:
    candidates: list[Path] = []

    env_lib = os.environ.get("PROARCHIVE_LZO_LIB")
    if env_lib:
        candidates.append(Path(env_lib).expanduser())

    try:
        brew_prefix = subprocess.check_output(
            ["brew", "--prefix", "lzo"],
            text=True,
        ).strip()
        lib_dir = Path(brew_prefix) / "lib"
        candidates.extend(
            [
                lib_dir / "liblzo2.2.dylib",
                lib_dir / "liblzo2.dylib",
            ]
        )
    except Exception:
        # Homebrew may not be installed in CI/build environments.
        pass

    lib = _first_existing(candidates)
    return [lib] if lib else []


binaries: list[tuple[str, str]] = []

ffmpeg_bin = _resolve_ffmpeg_binary()
if ffmpeg_bin is not None:
    binaries.append((str(ffmpeg_bin), "bin"))

for lib in _resolve_lzo_library_candidates():
    binaries.append((str(lib), "lib"))


a = Analysis(
    [str(script_path)],
    pathex=[str(project_root), str(project_root / "src")],
    binaries=binaries,
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="procreate-to-tif-cli",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="procreate-to-tif-cli",
)
