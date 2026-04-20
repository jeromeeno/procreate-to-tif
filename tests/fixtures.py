from __future__ import annotations

import plistlib
import struct
import zipfile
from pathlib import Path

import lzo


SAMPLE_SIZE = (2, 2)
SAMPLE_TILE_SIZE = 2
SAMPLE_LAYER_NAMES = ["Sketch", "Color"]
SAMPLE_COMPOSITE_UUID = "COMPOSITE-UUID"


def _solid_rgba_chunk(rgba: tuple[int, int, int, int], width: int, height: int) -> bytes:
    return bytes(rgba) * (width * height)


def create_sample_procreate_archive(path: Path) -> Path:
    width, height = SAMPLE_SIZE
    layers = [
        {
            "UUID": "LAYER-SKETCH",
            "name": SAMPLE_LAYER_NAMES[0],
            "type": 0,
            "opacity": 1.0,
            "hidden": False,
            "blend": 0,
            "clipped": False,
            "animationHeldLength": 0,
        },
        {
            "UUID": "LAYER-COLOR",
            "name": SAMPLE_LAYER_NAMES[1],
            "type": 0,
            "opacity": 0.75,
            "hidden": False,
            "blend": 0,
            "clipped": False,
            "animationHeldLength": 0,
        },
    ]

    document = {
        "size": f"{{{width}, {height}}}",
        "tileSize": SAMPLE_TILE_SIZE,
        "SilicaDocumentArchiveDPIKey": 144.0,
        "orientation": 1,
        "flippedHorizontally": False,
        "flippedVertically": False,
        "backgroundColor": struct.pack("<4f", 1.0, 1.0, 1.0, 1.0),
        "backgroundHidden": False,
        "animation": {
            "enabled": False,
            "animationMode": 0,
            "playbackMode": 1,
            "playbackDirection": 0,
            "frameRate": 12.0,
        },
        "isFirstItemAnimationForeground": False,
        "isLastItemAnimationBackground": False,
        "layers": {"NS.objects": layers},
        "composite": {"UUID": SAMPLE_COMPOSITE_UUID},
    }
    archive = {
        "$version": 100000,
        "$archiver": "NSKeyedArchiver",
        "$objects": ["$null"],
        "$top": {"root": document},
    }

    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as zip_file:
        zip_file.writestr(
            "Document.archive",
            plistlib.dumps(archive, fmt=plistlib.FMT_BINARY, sort_keys=False),
        )
        zip_file.writestr(
            "LAYER-SKETCH/0~0.chunk",
            lzo.compress(_solid_rgba_chunk((255, 0, 0, 255), width, height), 1, False),
        )
        zip_file.writestr(
            "LAYER-COLOR/0~0.chunk",
            lzo.compress(_solid_rgba_chunk((0, 255, 0, 128), width, height), 1, False),
        )

    return path
