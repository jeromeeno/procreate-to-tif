from __future__ import annotations

import ctypes
import math
import shutil
import subprocess
import zipfile
from dataclasses import dataclass
from typing import Iterable

import lzo
import lz4.block
from PIL import Image


@dataclass(frozen=True)
class _ChunkEntry:
    name: str
    codec: str


_COMPRESSION_ALGO_LZ4 = 0x100


def _compression_decode_lz4(src: bytes, dst_size: int) -> bytes | None:
    try:
        lib = ctypes.CDLL("/usr/lib/libcompression.dylib")
    except OSError:
        return None

    decode = lib.compression_decode_buffer
    decode.argtypes = [
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_int,
    ]
    decode.restype = ctypes.c_size_t

    dst = ctypes.create_string_buffer(dst_size)
    produced = decode(dst, dst_size, src, len(src), None, _COMPRESSION_ALGO_LZ4)
    if produced == 0:
        return None
    return bytes(dst.raw[:produced])


def _compression_tool_decode_lz4(src: bytes) -> bytes | None:
    if shutil.which("compression_tool") is None:
        return None

    result = subprocess.run(
        ["compression_tool", "-decode", "-a", "lz4"],
        input=src,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    return result.stdout


def _lz4_block_decode_lz4(src: bytes, dst_size: int) -> bytes | None:
    try:
        return lz4.block.decompress(src, uncompressed_size=dst_size)
    except Exception:
        return None


def _chunk_dimensions(
    col: int,
    row: int,
    columns: int,
    rows: int,
    tile_size: int,
    edge_width: int,
    edge_height: int,
) -> tuple[int, int]:
    tile_w = edge_width if (col + 1 == columns) else tile_size
    tile_h = edge_height if (row + 1 == rows) else tile_size
    return tile_w, tile_h


def _list_layer_chunks(zip_file: zipfile.ZipFile, layer_uuid: str) -> dict[tuple[int, int], _ChunkEntry]:
    prefix = f"{layer_uuid}/"
    chunks: dict[tuple[int, int], _ChunkEntry] = {}
    for name in zip_file.namelist():
        if not name.startswith(prefix):
            continue
        suffix = name[len(prefix):]
        if suffix.count("~") != 1:
            continue
        coord, dot, extension = suffix.partition(".")
        if not dot:
            continue
        if extension == "chunk":
            codec = "lzo"
        elif extension == "lz4":
            codec = "lz4"
        else:
            continue

        col_text, row_text = coord.split("~", 1)
        if not col_text.isdigit() or not row_text.isdigit():
            continue

        key = (int(col_text), int(row_text))
        existing = chunks.get(key)
        if existing is None or (existing.codec == "lzo" and codec == "lz4"):
            chunks[key] = _ChunkEntry(name=name, codec=codec)
    return chunks


def layer_has_chunks(zip_file: zipfile.ZipFile, layer_uuid: str) -> bool:
    prefix = f"{layer_uuid}/"
    return any(
        name.startswith(prefix) and (name.endswith(".chunk") or name.endswith(".lz4"))
        for name in zip_file.namelist()
    )


def _decompress_chunk(
    compressed: bytes,
    width: int,
    height: int,
    layer_uuid: str,
    col: int,
    row: int,
    codec: str,
) -> tuple[bytes, int]:
    expected_rgba_size = width * height * 4
    expected_l_size = width * height

    if codec == "lzo":
        raw = lzo.decompress(compressed, False, expected_rgba_size)
        if len(raw) == expected_rgba_size:
            return raw, 4
        if len(raw) == expected_l_size:
            return raw, 1
    elif codec == "lz4":
        raw = _compression_decode_lz4(compressed, expected_rgba_size)
        if raw is None:
            raw = _lz4_block_decode_lz4(compressed, expected_rgba_size)
        if raw is None:
            raw = _compression_tool_decode_lz4(compressed)
        if raw is None:
            raise RuntimeError(
                f"LZ4 decode failed for {layer_uuid}/{col}~{row}.lz4. "
                "Install a cross-platform LZ4 decoder or, on macOS, ensure "
                "/usr/lib/libcompression.dylib or compression_tool is available."
            )
        if len(raw) == expected_rgba_size:
            return raw, 4
        if len(raw) == expected_l_size:
            return raw, 1
        raise ValueError(
            f"LZ4 chunk size mismatch for {layer_uuid}/{col}~{row}.lz4: "
            f"expected {expected_l_size} or {expected_rgba_size}, got {len(raw)}"
        )

    else:
        raise ValueError(f"Unsupported chunk codec: {codec}")

    raise ValueError(
        f"Chunk size mismatch for {layer_uuid}/{col}~{row}.chunk: "
        f"expected {expected_l_size} or {expected_rgba_size}, got {len(raw)}"
    )


def _raw_to_tile(raw: bytes, bytes_per_pixel: int, width: int, height: int, mode: str) -> Image.Image:
    if mode == "RGBA":
        if bytes_per_pixel == 4:
            return Image.frombytes("RGBA", (width, height), raw)
        alpha = Image.frombytes("L", (width, height), raw)
        tile = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        tile.putalpha(alpha)
        return tile
    if mode == "L":
        if bytes_per_pixel == 1:
            return Image.frombytes("L", (width, height), raw)
        return Image.frombytes("RGBA", (width, height), raw).split()[3]
    raise ValueError(f"Unsupported output mode: {mode}")


def _blank_image(mode: str, width: int, height: int) -> Image.Image:
    if mode == "RGBA":
        return Image.new("RGBA", (width, height), (0, 0, 0, 0))
    if mode == "L":
        return Image.new("L", (width, height), 0)
    raise ValueError(f"Unsupported output mode: {mode}")


def reconstruct_layer(
    zip_file: zipfile.ZipFile,
    layer_uuid: str,
    width: int,
    height: int,
    tile_size: int,
    mode: str = "auto",
) -> Image.Image:
    if mode not in {"auto", "RGBA", "L"}:
        raise ValueError(
            f"Unsupported mode {mode!r}. Expected 'auto', 'RGBA', or 'L'."
        )
    columns = math.ceil(width / tile_size)
    rows = math.ceil(height / tile_size)
    edge_width = width % tile_size or tile_size
    edge_height = height % tile_size or tile_size

    chunks = _list_layer_chunks(zip_file, layer_uuid)
    if not chunks:
        fallback_mode = "RGBA" if mode == "auto" else mode
        return _blank_image(fallback_mode, width, height)

    actual_mode = None if mode == "auto" else mode
    canvas: Image.Image | None = None
    transpose_flip_tb = Image.Transpose.FLIP_TOP_BOTTOM

    for col in range(columns):
        for row in range(rows):
            tile_width, tile_height = _chunk_dimensions(
                col=col,
                row=row,
                columns=columns,
                rows=rows,
                tile_size=tile_size,
                edge_width=edge_width,
                edge_height=edge_height,
            )
            chunk = chunks.get((col, row))
            if chunk is None:
                continue

            compressed = zip_file.read(chunk.name)
            raw, bytes_per_pixel = _decompress_chunk(
                compressed=compressed,
                width=tile_width,
                height=tile_height,
                layer_uuid=layer_uuid,
                col=col,
                row=row,
                codec=chunk.codec,
            )
            if actual_mode is None:
                actual_mode = "RGBA" if bytes_per_pixel == 4 else "L"
            if canvas is None:
                canvas = _blank_image(actual_mode, width, height)

            tile = _raw_to_tile(raw, bytes_per_pixel, tile_width, tile_height, actual_mode)
            tile = tile.transpose(transpose_flip_tb)

            x = col * tile_size
            y = height - ((row + 1) * tile_size)
            if y < 0:
                y = 0
            canvas.paste(tile, (x, y))

    if canvas is None:
        fallback_mode = "RGBA" if mode == "auto" else mode
        canvas = _blank_image(fallback_mode, width, height)
    return canvas


def list_chunk_directories(zip_file: zipfile.ZipFile) -> Iterable[str]:
    return {
        name.split("/", 1)[0]
        for name in zip_file.namelist()
        if "/" in name and (name.endswith(".chunk") or name.endswith(".lz4"))
    }
