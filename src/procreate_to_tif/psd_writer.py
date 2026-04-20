from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image
from pytoshop import image_data
from pytoshop import image_resources
from pytoshop.enums import BlendMode, ChannelId, ColorChannel, ColorMode, Compression, Version
from pytoshop.user import nested_layers


@dataclass(frozen=True)
class LayerImageData:
    name: str
    image: Image.Image
    opacity: float
    hidden: bool
    blend: int


BLEND_MODE_MAP = {
    0: BlendMode.normal,
    1: BlendMode.multiply,
    2: BlendMode.screen,
    3: BlendMode.overlay,
    8: BlendMode.darken,
    9: BlendMode.lighten,
    17: BlendMode.color_dodge,
    18: BlendMode.color_burn,
}


def map_blend_mode(procreate_blend: int) -> BlendMode:
    return BLEND_MODE_MAP.get(procreate_blend, BlendMode.normal)


def _crop_to_alpha_bounds(arr: np.ndarray) -> tuple[np.ndarray, int, int]:
    alpha = arr[:, :, 3]
    ys, xs = np.nonzero(alpha)
    if xs.size == 0:
        # Keep a minimally non-empty layer record so fully transparent
        # layers remain in the PSD layer stack.
        sentinel = np.zeros((1, 1, 4), dtype=np.uint8)
        sentinel[0, 0, 3] = 1
        return sentinel, 0, 0
    left = int(xs.min())
    right = int(xs.max()) + 1
    top = int(ys.min())
    bottom = int(ys.max()) + 1
    return arr[top:bottom, left:right, :], top, left


def _layer_to_nested(layer: LayerImageData) -> nested_layers.Image:
    rgba = layer.image.convert("RGBA")
    arr = np.asarray(rgba, dtype=np.uint8)
    arr, top, left = _crop_to_alpha_bounds(arr)
    opacity = max(0, min(255, int(round(layer.opacity * 255.0))))
    height, width, _ = arr.shape
    image_layer = nested_layers.Image(
        name=layer.name,
        visible=not layer.hidden,
        opacity=opacity,
        blend_mode=map_blend_mode(layer.blend),
        top=top,
        left=left,
        bottom=top + height,
        right=left + width,
        channels={},
        color_mode=ColorMode.rgb,  # required for set_channel helpers
    )
    image_layer.set_channel(ColorChannel.red, arr[:, :, 0])
    image_layer.set_channel(ColorChannel.green, arr[:, :, 1])
    image_layer.set_channel(ColorChannel.blue, arr[:, :, 2])
    image_layer.channels[ChannelId.transparency] = arr[:, :, 3]
    return image_layer


def _add_icc_profile(psd, icc_profile: bytes) -> None:
    icc_block = image_resources.GenericImageResourceBlock(
        name="ICC Profile",
        resource_id=image_resources.enums.ImageResourceID.icc_profile,
        data=icc_profile,
    )
    if psd.image_resources is None:
        psd.image_resources = image_resources.ImageResources(blocks=[icc_block])
    else:
        psd.image_resources.blocks.append(icc_block)


def _set_composite_image(psd, composite_image: Image.Image, compression: Compression) -> None:
    rgb = np.asarray(composite_image.convert("RGB"), dtype=np.uint8)
    channels = np.stack(
        [rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]],
        axis=0,
    )
    psd.image_data = image_data.ImageData(channels=channels, compression=compression)


def write_layered_psd(
    layers: list[LayerImageData],
    width: int,
    height: int,
    output_path: Path,
    icc_profile: bytes | None = None,
    composite_image: Image.Image | None = None,
) -> None:
    nested = [_layer_to_nested(layer) for layer in layers]
    # Prefer maximum compatibility with Photoshop builds (including older/iPad variants).
    # We still get substantial size savings from tight layer bounds.
    compression = Compression.raw
    psd = nested_layers.nested_layers_to_psd(
        nested,
        color_mode=ColorMode.rgb,
        version=Version.version_1,
        compression=compression,
        depth=8,
        size=(width, height),
    )
    if composite_image is not None:
        _set_composite_image(psd, composite_image=composite_image, compression=compression)
    if icc_profile:
        _add_icc_profile(psd, icc_profile)
    with output_path.open("wb") as handle:
        psd.write(handle)
