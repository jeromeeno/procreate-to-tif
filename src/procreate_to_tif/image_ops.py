from __future__ import annotations

from PIL import Image


def apply_orientation(
    image: Image.Image,
    orientation: int,
    flipped_horizontally: bool,
    flipped_vertically: bool,
) -> Image.Image:
    if orientation == 2:
        image = image.rotate(180, expand=True)
    elif orientation == 3:
        image = image.rotate(90, expand=True)
    elif orientation == 4:
        image = image.rotate(-90, expand=True)

    # For 90-degree rotations, horizontal/vertical axes swap.
    if flipped_horizontally:
        if orientation in (1, 2):
            image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        else:
            image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    if flipped_vertically:
        if orientation in (1, 2):
            image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        else:
            image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return image


def unpremultiply_rgba(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    raw = bytearray(rgba.tobytes())
    for idx in range(0, len(raw), 4):
        alpha = raw[idx + 3]
        if alpha == 0:
            raw[idx] = 0
            raw[idx + 1] = 0
            raw[idx + 2] = 0
        elif alpha < 255:
            scale = 255.0 / float(alpha)
            raw[idx] = min(255, int(raw[idx] * scale + 0.5))
            raw[idx + 1] = min(255, int(raw[idx + 1] * scale + 0.5))
            raw[idx + 2] = min(255, int(raw[idx + 2] * scale + 0.5))
    return Image.frombytes("RGBA", rgba.size, bytes(raw))
