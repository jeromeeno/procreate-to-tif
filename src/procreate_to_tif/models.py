from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass(frozen=True)
class ProcreateLayerMeta:
    index: int
    uuid: str
    name: str
    layer_type: int
    opacity: float
    hidden: bool
    blend: int
    clipped: bool
    animation_held_length: int


@dataclass(frozen=True)
class ProcreateDocumentMeta:
    source_path: Path
    width: int
    height: int
    tile_size: int
    dpi: float
    orientation: int
    flipped_horizontally: bool
    flipped_vertically: bool
    background_color_rgba: Optional[tuple[int, int, int, int]]
    background_hidden: bool
    animation_enabled: bool
    animation_mode: Optional[int]
    playback_mode: Optional[int]
    playback_direction: Optional[int]
    frame_rate: Optional[float]
    is_first_item_animation_foreground: bool
    is_last_item_animation_background: bool
    icc_name: Optional[str]
    icc_data: Optional[bytes]
    content_layers: list[ProcreateLayerMeta]
    composite_uuid: Optional[str]
    mask_uuid: Optional[str]
