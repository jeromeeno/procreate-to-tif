from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


_SEGMENT_RE = re.compile(r"segment-(\d+)\.mp4$", re.IGNORECASE)


def _segment_sort_key(name: str) -> tuple[int, int | str]:
    match = _SEGMENT_RE.search(name)
    if match:
        return (0, int(match.group(1)))
    return (1, name)


def _list_timelapse_segments(zip_file: zipfile.ZipFile) -> list[str]:
    return sorted(
        [
            name
            for name in zip_file.namelist()
            if name.startswith("video/segments/") and name.lower().endswith(".mp4")
        ],
        key=_segment_sort_key,
    )


def _ffmpeg_concat_file_line(path: Path) -> str:
    escaped = str(path).replace("'", "'\\''")
    return f"file '{escaped}'\n"


def _run_ffmpeg_concat(segment_paths: list[Path], output_path: Path, ffmpeg_bin: str) -> None:
    with tempfile.TemporaryDirectory(prefix="procreate_concat_") as tmpdir:
        list_file = Path(tmpdir) / "segments.txt"
        list_file.write_text(
            "".join(_ffmpeg_concat_file_line(path) for path in segment_paths),
            encoding="utf-8",
        )

        copy_cmd = [
            ffmpeg_bin,
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(list_file),
            "-c",
            "copy",
            str(output_path),
        ]
        copy_result = subprocess.run(
            copy_cmd,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
        )
        if copy_result.returncode == 0:
            return

        transcode_cmd = [
            ffmpeg_bin,
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(list_file),
            "-c:v",
            "libx264",
            "-preset",
            "fast",
            "-crf",
            "18",
            "-pix_fmt",
            "yuv420p",
            "-c:a",
            "aac",
            "-movflags",
            "+faststart",
            str(output_path),
        ]
        transcode_result = subprocess.run(
            transcode_cmd,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
        )
        if transcode_result.returncode != 0:
            copy_stderr = copy_result.stderr.strip()
            transcode_stderr = transcode_result.stderr.strip()
            raise RuntimeError(
                "Failed to stitch timelapse segments with ffmpeg.\n"
                f"copy mode error: {copy_stderr}\n"
                f"transcode mode error: {transcode_stderr}"
            )


def _unique_existing_executables(candidates: list[Path]) -> list[Path]:
    unique: list[Path] = []
    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.expanduser().resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        if resolved.is_file() and os.access(resolved, os.X_OK):
            unique.append(resolved)
    return unique


def _resolve_ffmpeg_binary(ffmpeg_bin: str) -> str | None:
    candidates: list[Path] = []

    env_override = os.environ.get("PROARCHIVE_FFMPEG_BIN")
    if env_override:
        candidates.append(Path(env_override))

    ffmpeg_path = Path(ffmpeg_bin).expanduser()
    if ffmpeg_path.is_absolute():
        candidates.append(ffmpeg_path)
    elif ffmpeg_path.parts and ffmpeg_path.parts != ("ffmpeg",):
        candidates.append((Path.cwd() / ffmpeg_path))

    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).resolve().parent
        candidates.extend(
            [
                exe_dir / "bin" / "ffmpeg",
                exe_dir / "ffmpeg",
                exe_dir / "_internal" / "bin" / "ffmpeg",
                exe_dir.parent / "Resources" / "bin" / "ffmpeg",
                exe_dir.parent / "Resources" / "backend" / "bin" / "ffmpeg",
            ]
        )

    meipass = getattr(sys, "_MEIPASS", None)
    if meipass:
        meipass_dir = Path(str(meipass))
        candidates.extend(
            [
                meipass_dir / "bin" / "ffmpeg",
                meipass_dir / "ffmpeg",
            ]
        )

    for path in _unique_existing_executables(candidates):
        return str(path)

    discovered = shutil.which(ffmpeg_bin)
    if discovered:
        return discovered
    return None


def stitch_timelapse_segments(
    zip_file: zipfile.ZipFile,
    output_path: Path,
    ffmpeg_bin: str = "ffmpeg",
) -> bool:
    segment_names = _list_timelapse_segments(zip_file)
    if not segment_names:
        return False

    output_path.parent.mkdir(parents=True, exist_ok=True)

    if len(segment_names) == 1:
        output_path.write_bytes(zip_file.read(segment_names[0]))
        return True

    ffmpeg_resolved = _resolve_ffmpeg_binary(ffmpeg_bin)
    if ffmpeg_resolved is None:
        raise RuntimeError(
            "ffmpeg is required for timelapse stitching but was not found. "
            "Set PROARCHIVE_FFMPEG_BIN or bundle ffmpeg at bin/ffmpeg next to the CLI."
        )

    with tempfile.TemporaryDirectory(prefix="procreate_segments_") as tmpdir:
        tmp_dir_path = Path(tmpdir)
        segment_paths: list[Path] = []
        for index, name in enumerate(segment_names):
            segment_path = tmp_dir_path / f"{index:05d}.mp4"
            segment_path.write_bytes(zip_file.read(name))
            segment_paths.append(segment_path)

        _run_ffmpeg_concat(
            segment_paths=segment_paths,
            output_path=output_path,
            ffmpeg_bin=ffmpeg_resolved,
        )
    return True
