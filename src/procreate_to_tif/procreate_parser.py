from __future__ import annotations

import plistlib
import re
import struct
import zipfile
from pathlib import Path
from typing import Any, Optional

from .models import ProcreateDocumentMeta, ProcreateLayerMeta

_SIZE_RE = re.compile(r"^\{\s*(\d+)\s*,\s*(\d+)\s*\}$")


def _deref(objects: list[Any], value: Any) -> Any:
    if isinstance(value, plistlib.UID):
        return objects[value.data]
    return value


def _parse_size(raw: Any) -> tuple[int, int]:
    if isinstance(raw, str):
        match = _SIZE_RE.match(raw)
        if not match:
            raise ValueError(f"Invalid canvas size format: {raw!r}")
        return int(match.group(1)), int(match.group(2))
    raise ValueError(f"Unsupported canvas size object type: {type(raw).__name__}")


def _as_str(objects: list[Any], value: Any) -> Optional[str]:
    resolved = _deref(objects, value)
    if resolved in (None, "$null"):
        return None
    if isinstance(resolved, str):
        return resolved
    return str(resolved)


def _decode_rgba_float_bytes(raw: Any) -> Optional[tuple[int, int, int, int]]:
    if not isinstance(raw, (bytes, bytearray)):
        return None
    if len(raw) != 16:
        return None
    values = struct.unpack("<4f", bytes(raw))
    if any(v < -0.001 or v > 1.001 for v in values):
        values = struct.unpack(">4f", bytes(raw))
    rgba = tuple(
        max(0, min(255, int(round(max(0.0, min(1.0, channel)) * 255.0))))
        for channel in values
    )
    return rgba  # type: ignore[return-value]


def parse_document_archive(zip_file: zipfile.ZipFile, source_path: Path) -> ProcreateDocumentMeta:
    plist = plistlib.loads(zip_file.read("Document.archive"))
    objects = plist["$objects"]
    top = plist["$top"]
    root_ref = top.get("root")
    if root_ref is None:
        raise ValueError("Document archive missing $top.root reference")

    document = _deref(objects, root_ref)
    if not isinstance(document, dict):
        raise ValueError("Root document object is not a dictionary")

    width, height = _parse_size(_deref(objects, document["size"]))
    tile_size = int(document["tileSize"])
    dpi = float(document.get("SilicaDocumentArchiveDPIKey", 72.0))
    orientation = int(document.get("orientation", 1))
    flipped_horizontally = bool(document.get("flippedHorizontally", False))
    flipped_vertically = bool(document.get("flippedVertically", False))
    background_color_rgba = _decode_rgba_float_bytes(
        _deref(objects, document.get("backgroundColor"))
    )
    background_hidden = bool(document.get("backgroundHidden", False))

    animation_enabled = False
    animation_mode: Optional[int] = None
    playback_mode: Optional[int] = None
    playback_direction: Optional[int] = None
    frame_rate: Optional[float] = None
    is_first_item_animation_foreground = bool(
        document.get("isFirstItemAnimationForeground", False)
    )
    is_last_item_animation_background = bool(
        document.get("isLastItemAnimationBackground", False)
    )
    animation_obj = _deref(objects, document.get("animation"))
    if isinstance(animation_obj, dict):
        if "enabled" in animation_obj:
            animation_enabled = bool(_deref(objects, animation_obj.get("enabled")))
        animation_mode_raw = _deref(objects, animation_obj.get("animationMode"))
        if animation_mode_raw is not None:
            animation_mode = int(animation_mode_raw)
            if animation_mode != 0:
                animation_enabled = True
        playback_mode_raw = _deref(objects, animation_obj.get("playbackMode"))
        if playback_mode_raw is not None:
            playback_mode = int(playback_mode_raw)
        playback_direction_raw = _deref(objects, animation_obj.get("playbackDirection"))
        if playback_direction_raw is not None:
            playback_direction = int(playback_direction_raw)
        frame_rate_raw = _deref(objects, animation_obj.get("frameRate"))
        if frame_rate_raw is not None:
            frame_rate = float(frame_rate_raw)

    icc_name = None
    icc_data = None
    color_profile_ref = document.get("colorProfile")
    color_profile = _deref(objects, color_profile_ref) if color_profile_ref is not None else None
    if isinstance(color_profile, dict):
        icc_name = _as_str(objects, color_profile.get("SiColorProfileArchiveICCNameKey"))
        raw_icc = color_profile.get("SiColorProfileArchiveICCDataKey")
        if isinstance(raw_icc, (bytes, bytearray)):
            icc_data = bytes(raw_icc)

    layers_ref = document.get("layers")
    layers_obj = _deref(objects, layers_ref) if layers_ref is not None else None
    layer_refs = layers_obj.get("NS.objects", []) if isinstance(layers_obj, dict) else []

    content_layers: list[ProcreateLayerMeta] = []
    for index, layer_ref in enumerate(layer_refs):
        layer_obj = _deref(objects, layer_ref)
        if not isinstance(layer_obj, dict):
            continue
        layer_type = int(layer_obj.get("type", 0))
        if layer_type != 0:
            continue
        name = _as_str(objects, layer_obj.get("name")) or f"Layer {index + 1}"
        uuid = _as_str(objects, layer_obj.get("UUID"))
        if not uuid:
            continue
        content_layers.append(
            ProcreateLayerMeta(
                index=index,
                uuid=uuid,
                name=name,
                layer_type=layer_type,
                opacity=float(layer_obj.get("opacity", 1.0)),
                hidden=bool(layer_obj.get("hidden", False)),
                blend=int(layer_obj.get("blend", 0)),
                clipped=bool(layer_obj.get("clipped", False)),
                animation_held_length=int(layer_obj.get("animationHeldLength", 0)),
            )
        )

    composite_uuid = None
    composite_ref = document.get("composite")
    composite_obj = _deref(objects, composite_ref) if composite_ref is not None else None
    if isinstance(composite_obj, dict):
        composite_uuid = _as_str(objects, composite_obj.get("UUID"))

    mask_uuid = None
    mask_ref = document.get("mask")
    mask_obj = _deref(objects, mask_ref) if mask_ref is not None else None
    if isinstance(mask_obj, dict):
        mask_uuid = _as_str(objects, mask_obj.get("UUID"))

    return ProcreateDocumentMeta(
        source_path=source_path,
        width=width,
        height=height,
        tile_size=tile_size,
        dpi=dpi,
        orientation=orientation,
        flipped_horizontally=flipped_horizontally,
        flipped_vertically=flipped_vertically,
        background_color_rgba=background_color_rgba,
        background_hidden=background_hidden,
        animation_enabled=animation_enabled,
        animation_mode=animation_mode,
        playback_mode=playback_mode,
        playback_direction=playback_direction,
        frame_rate=frame_rate,
        is_first_item_animation_foreground=is_first_item_animation_foreground,
        is_last_item_animation_background=is_last_item_animation_background,
        icc_name=icc_name,
        icc_data=icc_data,
        content_layers=content_layers,
        composite_uuid=composite_uuid,
        mask_uuid=mask_uuid,
    )


def parse_procreate_file(path: Path) -> ProcreateDocumentMeta:
    with zipfile.ZipFile(path) as zip_file:
        return parse_document_archive(zip_file, source_path=path)
