from __future__ import annotations

import tempfile
import unittest
import zipfile
from pathlib import Path

import numpy as np
import lz4.block

from procreate_to_tif.tile_decoder import layer_has_chunks, reconstruct_layer


def _encode_lz4(payload: bytes) -> bytes:
    return lz4.block.compress(payload, store_size=False)


class TileDecoderLz4Tests(unittest.TestCase):
    def test_reconstruct_layer_from_lz4_chunk(self) -> None:
        layer_uuid = "LAYER-UUID"
        raw = bytes([10, 20, 30, 40] * 4)  # 2x2 RGBA
        compressed = _encode_lz4(raw)

        with tempfile.TemporaryDirectory() as tmpdir:
            archive_path = Path(tmpdir) / "sample.procreate"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(f"{layer_uuid}/0~0.lz4", compressed)

            with zipfile.ZipFile(archive_path) as archive:
                self.assertTrue(layer_has_chunks(archive, layer_uuid))
                image = reconstruct_layer(
                    zip_file=archive,
                    layer_uuid=layer_uuid,
                    width=2,
                    height=2,
                    tile_size=2,
                    mode="RGBA",
                )

        arr = np.asarray(image, dtype=np.uint8)
        self.assertEqual(arr.shape, (2, 2, 4))
        self.assertTrue((arr[:, :, 0] == 10).all())
        self.assertTrue((arr[:, :, 1] == 20).all())
        self.assertTrue((arr[:, :, 2] == 30).all())
        self.assertTrue((arr[:, :, 3] == 40).all())


if __name__ == "__main__":
    unittest.main()
