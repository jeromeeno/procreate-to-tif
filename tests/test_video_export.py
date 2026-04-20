from __future__ import annotations

import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from procreate_to_tif.video_export import _resolve_ffmpeg_binary


def _make_executable(path: Path) -> None:
    path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    mode = path.stat().st_mode
    path.chmod(mode | stat.S_IXUSR)


class VideoExportTests(unittest.TestCase):
    def test_resolve_ffmpeg_from_env_override(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            ffmpeg_path = Path(tmpdir) / "ffmpeg"
            _make_executable(ffmpeg_path)

            with patch.dict(os.environ, {"PROARCHIVE_FFMPEG_BIN": str(ffmpeg_path)}, clear=False):
                resolved = _resolve_ffmpeg_binary("ffmpeg")

            self.assertEqual(resolved, str(ffmpeg_path.resolve()))

    def test_resolve_ffmpeg_from_explicit_absolute_arg(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            ffmpeg_path = Path(tmpdir) / "ffmpeg-custom"
            _make_executable(ffmpeg_path)

            with patch.dict(os.environ, {}, clear=True), patch("shutil.which", return_value=None):
                resolved = _resolve_ffmpeg_binary(str(ffmpeg_path))

            self.assertEqual(resolved, str(ffmpeg_path.resolve()))

    def test_resolve_ffmpeg_returns_none_when_not_found(self) -> None:
        with patch.dict(os.environ, {}, clear=True), patch("shutil.which", return_value=None):
            resolved = _resolve_ffmpeg_binary("ffmpeg")

        self.assertIsNone(resolved)


if __name__ == "__main__":
    unittest.main()
