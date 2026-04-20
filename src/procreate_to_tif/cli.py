from __future__ import annotations

import argparse
import glob
import json
from pathlib import Path
from typing import Iterable

from .pipeline import convert_procreate_file


def _expand_inputs(patterns: Iterable[str]) -> list[Path]:
    results: list[Path] = []
    for pattern in patterns:
        matches = glob.glob(pattern)
        if matches:
            results.extend(Path(match) for match in matches)
        else:
            results.append(Path(pattern))
    # Keep user order but dedupe exact paths.
    deduped: list[Path] = []
    seen: set[Path] = set()
    for path in results:
        resolved = path.resolve()
        if resolved in seen:
            continue
        seen.add(resolved)
        deduped.append(path)
    return deduped


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Convert .procreate files to layered/flat/animated outputs and optional timelapse MP4."
    )
    parser.add_argument(
        "files",
        nargs="+",
        help=".procreate files or glob patterns (e.g. *.procreate)",
    )
    parser.add_argument(
        "--outdir",
        type=Path,
        default=Path("exports"),
        help="Output directory (default: ./exports).",
    )
    parser.add_argument(
        "--no-psd",
        action="store_true",
        help="Do not write layered PSD output.",
    )
    parser.add_argument(
        "--flat-png",
        action="store_true",
        help="Also write a flattened PNG.",
    )
    parser.add_argument(
        "--flat-jpg",
        action="store_true",
        help="Also write a flattened JPG.",
    )
    parser.add_argument(
        "--animated-webp",
        action="store_true",
        help="Write animated WebP for files with animation metadata.",
    )
    parser.add_argument(
        "--animated-gif",
        action="store_true",
        help="Write animated GIF for files with animation metadata.",
    )
    parser.add_argument(
        "--timelapse-mp4",
        action="store_true",
        help="Stitch Procreate timelapse video segments to MP4 when available.",
    )
    parser.add_argument(
        "--jpg-quality",
        type=int,
        default=95,
        help="JPG quality (1-100, default: 95).",
    )
    parser.add_argument(
        "--apply-mask",
        action="store_true",
        help="Apply document mask during export (off by default).",
    )
    parser.add_argument(
        "--no-unpremultiply",
        action="store_true",
        help="Skip RGBA un-premultiplication.",
    )
    parser.add_argument(
        "--no-background",
        action="store_true",
        help="Do not add Procreate document background color as bottom PSD layer.",
    )
    parser.add_argument(
        "--if-exists",
        choices=("overwrite", "skip", "fail"),
        default="overwrite",
        help="How to handle existing output files: overwrite (default), skip, or fail.",
    )
    parser.add_argument(
        "--log-format",
        choices=("text", "jsonl"),
        default="text",
        help="Console output format: text (default) or jsonl for machine-readable progress.",
    )
    return parser


def _emit_jsonl(event: str, **payload: object) -> None:
    print(json.dumps({"event": event, **payload}, separators=(",", ":"), ensure_ascii=False), flush=True)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if (
        args.no_psd
        and not args.flat_png
        and not args.flat_jpg
        and not args.animated_webp
        and not args.animated_gif
        and not args.timelapse_mp4
    ):
        parser.error(
            "No outputs selected. Remove --no-psd or add --flat-png/--flat-jpg/--animated-webp/--animated-gif/--timelapse-mp4."
        )

    files = _expand_inputs(args.files)
    if not files:
        parser.error("No input files matched.")

    failures = 0
    total_files = len(files)
    if args.log_format == "jsonl":
        _emit_jsonl("run_start", total=total_files)

    for index, src in enumerate(files, start=1):
        src_resolved = src.resolve()
        if args.log_format == "jsonl":
            _emit_jsonl(
                "file_start",
                file=str(src_resolved),
                index=index,
                total=total_files,
            )
        if not src.exists():
            failures += 1
            message = f"Missing file: {src}"
            if args.log_format == "jsonl":
                _emit_jsonl(
                    "file_error",
                    file=str(src_resolved),
                    index=index,
                    total=total_files,
                    message=message,
                    error_code="missing_input",
                )
            else:
                print(f"[ERROR] {message}")
            continue

        output_dir = args.outdir
        if args.log_format == "text":
            print(f"[INFO] Converting: {src}")

        def emit_output_event(
            output: str,
            status: str,
            path: Path | None = None,
            message: str | None = None,
        ) -> None:
            if args.log_format != "jsonl":
                return
            payload: dict[str, object] = {
                "file": str(src_resolved),
                "index": index,
                "total": total_files,
                "output": output,
                "status": status,
            }
            if path is not None:
                payload["path"] = str(path)
            if message:
                payload["message"] = message
            _emit_jsonl("file_output", **payload)

        try:
            result = convert_procreate_file(
                source_path=src,
                output_dir=output_dir,
                write_psd=not args.no_psd,
                write_flat_png=args.flat_png,
                write_flat_jpg=args.flat_jpg,
                write_animated_webp=args.animated_webp,
                write_animated_gif=args.animated_gif,
                write_timelapse_mp4=args.timelapse_mp4,
                apply_mask=args.apply_mask,
                include_background=not args.no_background,
                unpremultiply=not args.no_unpremultiply,
                jpg_quality=args.jpg_quality,
                if_exists=args.if_exists,
                on_output_event=emit_output_event,
            )
        except Exception as exc:
            failures += 1
            if args.log_format == "jsonl":
                _emit_jsonl(
                    "file_error",
                    file=str(src_resolved),
                    index=index,
                    total=total_files,
                    message=str(exc),
                    error_code="conversion_failed",
                )
            else:
                print(f"[ERROR] {src}: {exc}")
            continue

        if args.log_format == "jsonl":
            outputs: dict[str, str] = {}
            if result.psd_path:
                outputs["psd"] = str(result.psd_path)
            if result.png_path:
                outputs["png"] = str(result.png_path)
            if result.jpg_path:
                outputs["jpg"] = str(result.jpg_path)
            if result.webp_path:
                outputs["webp"] = str(result.webp_path)
            if result.gif_path:
                outputs["gif"] = str(result.gif_path)
            if result.timelapse_mp4_path:
                outputs["mp4"] = str(result.timelapse_mp4_path)

            requested_outputs: list[str] = []
            if not args.no_psd:
                requested_outputs.append("psd")
            if args.flat_png:
                requested_outputs.append("png")
            if args.flat_jpg:
                requested_outputs.append("jpg")
            if args.animated_webp:
                requested_outputs.append("webp")
            if args.animated_gif:
                requested_outputs.append("gif")
            if args.timelapse_mp4:
                requested_outputs.append("mp4")

            skipped = [output for output in requested_outputs if output not in outputs]

            payload: dict[str, object] = {
                "file": str(result.source),
                "index": index,
                "total": total_files,
                "width": result.width,
                "height": result.height,
                "layer_count": result.layer_count,
                "outputs": outputs,
            }
            if skipped:
                payload["skipped"] = skipped
            _emit_jsonl("file_success", **payload)
        else:
            if result.psd_path:
                print(
                    f"[OK] PSD: {result.psd_path} "
                    f"({result.width}x{result.height}, {result.layer_count} layers)"
                )
            if result.png_path:
                print(f"[OK] PNG: {result.png_path}")
            if result.jpg_path:
                print(f"[OK] JPG: {result.jpg_path}")
            if result.webp_path:
                print(f"[OK] WEBP: {result.webp_path}")
            elif args.animated_webp:
                print("[INFO] WEBP skipped (not detected as animated)")
            if result.gif_path:
                print(f"[OK] GIF: {result.gif_path}")
            elif args.animated_gif:
                print("[INFO] GIF skipped (not detected as animated)")
            if result.timelapse_mp4_path:
                print(f"[OK] MP4: {result.timelapse_mp4_path}")
            elif args.timelapse_mp4:
                print("[INFO] MP4 skipped (no timelapse segments found)")

    if args.log_format == "jsonl":
        _emit_jsonl(
            "run_complete",
            total=total_files,
            successes=total_files - failures,
            failures=failures,
        )

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
