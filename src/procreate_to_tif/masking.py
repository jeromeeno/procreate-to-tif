from __future__ import annotations

from PIL import Image, ImageChops


def extract_mask_alpha(mask_image: Image.Image) -> Image.Image:
    if mask_image.mode == "RGBA":
        return mask_image.split()[3]
    if mask_image.mode == "LA":
        return mask_image.split()[1]
    return mask_image.convert("L")


def apply_document_mask(image: Image.Image, mask_alpha: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    if mask_alpha.size != rgba.size:
        mask_alpha = mask_alpha.resize(rgba.size, Image.Resampling.BILINEAR)

    red, green, blue, alpha = rgba.split()
    combined_alpha = ImageChops.multiply(alpha, mask_alpha)
    return Image.merge("RGBA", (red, green, blue, combined_alpha))

