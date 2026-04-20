from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from PIL import Image
from pytoshop import PsdFile
from pytoshop.user import nested_layers

from procreate_to_tif.pipeline import convert_procreate_file
from procreate_to_tif.procreate_parser import parse_procreate_file
from tests.fixtures import (
    SAMPLE_COMPOSITE_UUID,
    SAMPLE_LAYER_NAMES,
    SAMPLE_SIZE,
    SAMPLE_TILE_SIZE,
    create_sample_procreate_archive,
)


class SmokeTests(unittest.TestCase):
    def test_parse_sample_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            sample_path = create_sample_procreate_archive(Path(tmpdir) / "sample.procreate")
            doc = parse_procreate_file(sample_path)

        self.assertEqual((doc.width, doc.height), SAMPLE_SIZE)
        self.assertEqual(doc.tile_size, SAMPLE_TILE_SIZE)
        self.assertEqual(doc.orientation, 1)
        self.assertEqual(len(doc.content_layers), len(SAMPLE_LAYER_NAMES))
        self.assertEqual(doc.composite_uuid, SAMPLE_COMPOSITE_UUID)
        self.assertFalse(doc.background_hidden)
        self.assertEqual(doc.background_color_rgba, (255, 255, 255, 255))
        self.assertFalse(doc.animation_enabled)
        self.assertEqual(doc.playback_mode, 1)
        self.assertEqual(doc.playback_direction, 0)
        self.assertEqual(doc.frame_rate, 12.0)
        self.assertFalse(doc.is_first_item_animation_foreground)
        self.assertFalse(doc.is_last_item_animation_background)

    def test_convert_sample(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            temp_root = Path(tmpdir)
            sample_path = create_sample_procreate_archive(temp_root / "sample.procreate")
            outdir = temp_root / "exports"
            result = convert_procreate_file(
                sample_path,
                output_dir=outdir,
                write_flat_png=True,
                write_flat_jpg=True,
            )

            self.assertTrue(result.psd_path.exists())
            self.assertIsNotNone(result.png_path)
            self.assertTrue(result.png_path and result.png_path.exists())
            self.assertIsNotNone(result.jpg_path)
            self.assertTrue(result.jpg_path and result.jpg_path.exists())
            self.assertIsNone(result.webp_path)
            self.assertIsNone(result.gif_path)
            self.assertIsNone(result.timelapse_mp4_path)
            self.assertEqual(result.layer_count, 3)

            with result.psd_path.open("rb") as handle:
                psd = PsdFile.read(handle)
            self.assertEqual((psd.width, psd.height), SAMPLE_SIZE)
            self.assertEqual(
                len(psd.layer_and_mask_info.layer_info.layer_records),
                3,
            )
            nested = nested_layers.psd_to_nested_layers(psd)
            expected_names = [layer.name for layer in parse_procreate_file(sample_path).content_layers]
            expected_names.append("Background Color")
            self.assertEqual(
                [layer.name for layer in nested],
                expected_names,
            )

            with Image.open(result.png_path) as png:
                self.assertEqual(png.size, SAMPLE_SIZE)
                self.assertEqual(png.mode, "RGBA")
            with Image.open(result.jpg_path) as jpg:
                self.assertEqual(jpg.size, SAMPLE_SIZE)
                self.assertEqual(jpg.mode, "RGB")

            animated = convert_procreate_file(
                sample_path,
                output_dir=outdir,
                write_psd=False,
                write_animated_webp=True,
                write_animated_gif=True,
            )
            self.assertIsNone(animated.webp_path)
            self.assertIsNone(animated.gif_path)

    def test_skip_existing_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            temp_root = Path(tmpdir)
            sample_path = create_sample_procreate_archive(temp_root / "sample.procreate")
            outdir = temp_root / "exports"
            outdir.mkdir(parents=True, exist_ok=True)
            existing_psd = outdir / f"{sample_path.stem}.psd"
            sentinel = b"existing-content"
            existing_psd.write_bytes(sentinel)

            result = convert_procreate_file(
                sample_path,
                output_dir=outdir,
                write_flat_png=False,
                write_flat_jpg=False,
                if_exists="skip",
            )

            self.assertIsNone(result.psd_path)
            self.assertEqual(existing_psd.read_bytes(), sentinel)


if __name__ == "__main__":
    unittest.main()
