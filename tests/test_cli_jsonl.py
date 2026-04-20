from __future__ import annotations

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from procreate_to_tif.cli import main
from procreate_to_tif.pipeline import ConversionResult


class CliJsonlTests(unittest.TestCase):
    def test_jsonl_emits_progress_for_success_and_missing_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            temp_root = Path(tmpdir)
            source = temp_root / "sample.procreate"
            source.write_bytes(b"")
            missing = temp_root / "missing.procreate"
            outdir = temp_root / "out"

            conversion = ConversionResult(
                source=source.resolve(),
                psd_path=outdir / "sample.psd",
                png_path=None,
                jpg_path=None,
                webp_path=None,
                gif_path=None,
                timelapse_mp4_path=None,
                width=1620,
                height=2841,
                layer_count=9,
            )

            output = io.StringIO()
            with patch("procreate_to_tif.cli.convert_procreate_file", return_value=conversion) as convert:
                with redirect_stdout(output):
                    exit_code = main(
                        [
                            "--log-format",
                            "jsonl",
                            "--outdir",
                            str(outdir),
                            str(source),
                            str(missing),
                        ]
                    )

            self.assertEqual(exit_code, 1)
            convert.assert_called_once()

            events = [json.loads(line) for line in output.getvalue().splitlines() if line.strip()]
            self.assertEqual(
                [event["event"] for event in events],
                ["run_start", "file_start", "file_success", "file_start", "file_error", "run_complete"],
            )
            self.assertEqual(events[0]["total"], 2)
            self.assertEqual(events[2]["index"], 1)
            self.assertEqual(events[2]["total"], 2)
            self.assertEqual(events[2]["outputs"], {"psd": str(outdir / "sample.psd")})
            self.assertEqual(events[4]["error_code"], "missing_input")
            self.assertEqual(events[4]["index"], 2)
            self.assertEqual(events[5]["successes"], 1)
            self.assertEqual(events[5]["failures"], 1)

    def test_jsonl_reports_skipped_optional_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            temp_root = Path(tmpdir)
            source = temp_root / "sample.procreate"
            source.write_bytes(b"")
            outdir = temp_root / "out"

            conversion = ConversionResult(
                source=source.resolve(),
                psd_path=outdir / "sample.psd",
                png_path=None,
                jpg_path=None,
                webp_path=None,
                gif_path=None,
                timelapse_mp4_path=None,
                width=100,
                height=200,
                layer_count=3,
            )

            output = io.StringIO()
            with patch("procreate_to_tif.cli.convert_procreate_file", return_value=conversion):
                with redirect_stdout(output):
                    exit_code = main(
                        [
                            "--log-format",
                            "jsonl",
                            "--animated-webp",
                            "--animated-gif",
                            "--timelapse-mp4",
                            "--outdir",
                            str(outdir),
                            str(source),
                        ]
                    )

            self.assertEqual(exit_code, 0)
            events = [json.loads(line) for line in output.getvalue().splitlines() if line.strip()]
            self.assertEqual(events[2]["event"], "file_success")
            self.assertEqual(events[2]["skipped"], ["webp", "gif", "mp4"])
            self.assertEqual(events[3]["event"], "run_complete")
            self.assertEqual(events[3]["failures"], 0)

    def test_jsonl_emits_per_output_progress_events(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            temp_root = Path(tmpdir)
            source = temp_root / "sample.procreate"
            source.write_bytes(b"")
            outdir = temp_root / "out"
            psd_path = outdir / "sample.psd"

            conversion = ConversionResult(
                source=source.resolve(),
                psd_path=psd_path,
                png_path=None,
                jpg_path=None,
                webp_path=None,
                gif_path=None,
                timelapse_mp4_path=None,
                width=120,
                height=240,
                layer_count=5,
            )

            def convert_side_effect(*args, **kwargs):
                callback = kwargs.get("on_output_event")
                self.assertIsNotNone(callback)
                callback("psd", "started", psd_path, None)
                callback("psd", "completed", psd_path, None)
                callback("webp", "skipped", None, "not_animated")
                return conversion

            output = io.StringIO()
            with patch("procreate_to_tif.cli.convert_procreate_file", side_effect=convert_side_effect):
                with redirect_stdout(output):
                    exit_code = main(
                        [
                            "--log-format",
                            "jsonl",
                            "--outdir",
                            str(outdir),
                            str(source),
                        ]
                    )

            self.assertEqual(exit_code, 0)
            events = [json.loads(line) for line in output.getvalue().splitlines() if line.strip()]
            self.assertEqual(
                [event["event"] for event in events],
                ["run_start", "file_start", "file_output", "file_output", "file_output", "file_success", "run_complete"],
            )
            self.assertEqual(events[2]["output"], "psd")
            self.assertEqual(events[2]["status"], "started")
            self.assertEqual(events[3]["status"], "completed")
            self.assertEqual(events[3]["path"], str(psd_path))
            self.assertEqual(events[4]["output"], "webp")
            self.assertEqual(events[4]["status"], "skipped")
            self.assertEqual(events[4]["message"], "not_animated")

    def test_if_exists_strategy_passed_to_converter(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            temp_root = Path(tmpdir)
            source = temp_root / "sample.procreate"
            source.write_bytes(b"")
            outdir = temp_root / "out"

            conversion = ConversionResult(
                source=source.resolve(),
                psd_path=None,
                png_path=None,
                jpg_path=None,
                webp_path=None,
                gif_path=None,
                timelapse_mp4_path=None,
                width=100,
                height=100,
                layer_count=1,
            )

            output = io.StringIO()
            with patch("procreate_to_tif.cli.convert_procreate_file", return_value=conversion) as convert:
                with redirect_stdout(output):
                    exit_code = main(
                        [
                            "--log-format",
                            "jsonl",
                            "--if-exists",
                            "skip",
                            "--no-psd",
                            "--flat-png",
                            "--outdir",
                            str(outdir),
                            str(source),
                        ]
                    )

            self.assertEqual(exit_code, 0)
            self.assertEqual(convert.call_args.kwargs["if_exists"], "skip")


if __name__ == "__main__":
    unittest.main()
