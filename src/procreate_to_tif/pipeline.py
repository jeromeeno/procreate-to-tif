from __future__ import annotations

import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Literal, Optional, Sequence

from PIL import Image

from .image_ops import apply_orientation, unpremultiply_rgba
from .masking import apply_document_mask, extract_mask_alpha
from .models import ProcreateDocumentMeta, ProcreateLayerMeta
from .procreate_parser import parse_document_archive
from .psd_writer import LayerImageData, write_layered_psd
from .tile_decoder import layer_has_chunks, reconstruct_layer
from .video_export import stitch_timelapse_segments


@dataclass(frozen=True)
class ConversionResult:
    source: Path
    psd_path: Path | None
    png_path: Path | None
    jpg_path: Path | None
    webp_path: Path | None
    gif_path: Path | None
    timelapse_mp4_path: Path | None
    width: int
    height: int
    layer_count: int


OutputEventCallback = Callable[[str, str, Optional[Path], Optional[str]], None]
ExistingOutputPolicy = Literal["overwrite", "skip", "fail"]


def _flatten_layers(layers: list[LayerImageData], width: int, height: int) -> Image.Image:
    flat = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    # Layer list is ordered top->bottom for PSD writing, so composite reversed.
    for layer in reversed(layers):
        if layer.hidden:
            continue
        flat.alpha_composite(layer.image.convert("RGBA"))
    return flat


def _write_png(
    image: Image.Image,
    output_path: Path,
    dpi: float,
    icc_profile: bytes | None,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGBA").save(
        output_path,
        format="PNG",
        dpi=(dpi, dpi),
        icc_profile=icc_profile,
    )


def _write_jpg(
    image: Image.Image,
    output_path: Path,
    dpi: float,
    icc_profile: bytes | None,
    quality: int,
    matte_rgb: tuple[int, int, int],
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    rgba = image.convert("RGBA")
    base = Image.new("RGB", rgba.size, matte_rgb)
    base.paste(rgba, mask=rgba.split()[3])
    base.save(
        output_path,
        format="JPEG",
        quality=max(1, min(100, int(quality))),
        optimize=True,
        dpi=(dpi, dpi),
        icc_profile=icc_profile,
    )


def _apply_playback_sequence(
    frames: Sequence[Image.Image],
    held_lengths: Sequence[int],
    playback_direction: int | None,
    playback_mode: int | None,
) -> tuple[list[Image.Image], list[int]]:
    if len(frames) != len(held_lengths):
        raise ValueError("frames and held_lengths must match")

    indices = list(range(len(frames)))
    if playback_direction == 1:
        indices.reverse()

    # Best-effort mapping: mode 2 behaves as ping-pong in current sample files.
    if playback_mode == 2 and len(indices) > 1:
        indices = indices + indices[-2:0:-1]

    ordered_frames = [frames[i] for i in indices]
    ordered_holds = [held_lengths[i] for i in indices]
    return ordered_frames, ordered_holds


def _build_frame_durations_ms(frame_rate: float | None, held_lengths: Sequence[int]) -> list[int]:
    fps = frame_rate if frame_rate and frame_rate > 0 else 15.0
    base = max(1, int(round(1000.0 / fps)))
    return [base * (1 + max(0, int(hold))) for hold in held_lengths]


def _write_animated_webp(
    frames: Sequence[Image.Image],
    durations_ms: Sequence[int],
    output_path: Path,
    loop_forever: bool,
) -> None:
    if not frames:
        return
    output_path.parent.mkdir(parents=True, exist_ok=True)
    first = frames[0].convert("RGBA")
    rest = [frame.convert("RGBA") for frame in frames[1:]]
    first.save(
        output_path,
        format="WEBP",
        save_all=True,
        append_images=rest,
        duration=list(durations_ms),
        loop=0 if loop_forever else 1,
        lossless=True,
        method=6,
    )


def _write_animated_gif(
    frames: Sequence[Image.Image],
    durations_ms: Sequence[int],
    output_path: Path,
    loop_forever: bool,
) -> None:
    if not frames:
        return
    output_path.parent.mkdir(parents=True, exist_ok=True)
    first = frames[0].convert("RGBA")
    rest = [frame.convert("RGBA") for frame in frames[1:]]
    first.save(
        output_path,
        format="GIF",
        save_all=True,
        append_images=rest,
        duration=list(durations_ms),
        loop=0 if loop_forever else 1,
        disposal=2,
        optimize=False,
    )


def _is_animation_candidate(document: ProcreateDocumentMeta, frame_count: int) -> bool:
    if frame_count < 2:
        return False
    if document.animation_enabled:
        return True
    if document.animation_mode is not None and document.animation_mode != 0:
        return True
    return False


def _compose_animation_frames(
    document: ProcreateDocumentMeta,
    frame_sources: Sequence[tuple[ProcreateLayerMeta, Image.Image]],
    include_background: bool,
) -> tuple[list[Image.Image], list[int]]:
    visible_sources = [
        (meta, image.convert("RGBA"))
        for meta, image in frame_sources
        if not meta.hidden
    ]
    if not visible_sources:
        return [], []

    sticky_background_image: Image.Image | None = None
    sticky_foreground_image: Image.Image | None = None

    start = 0
    end = len(visible_sources)
    if document.is_last_item_animation_background and end - start >= 2:
        sticky_background_image = visible_sources[end - 1][1]
        end -= 1
    if document.is_first_item_animation_foreground and end - start >= 2:
        sticky_foreground_image = visible_sources[start][1]
        start += 1

    sequence = visible_sources[start:end]
    if not sequence:
        return [], []

    base_bg = None
    if include_background and not document.background_hidden and document.background_color_rgba:
        base_bg = Image.new("RGBA", sequence[0][1].size, document.background_color_rgba)

    frames: list[Image.Image] = []
    held_lengths: list[int] = []
    for meta, frame_image in sequence:
        frame = Image.new("RGBA", frame_image.size, (0, 0, 0, 0))
        if base_bg is not None:
            frame.alpha_composite(base_bg)
        if sticky_background_image is not None:
            frame.alpha_composite(sticky_background_image)
        frame.alpha_composite(frame_image)
        if sticky_foreground_image is not None:
            frame.alpha_composite(sticky_foreground_image)
        frames.append(frame)
        held_lengths.append(meta.animation_held_length)
    return frames, held_lengths


def _reconstruct_oriented_rgba(
    zip_file: zipfile.ZipFile,
    document: ProcreateDocumentMeta,
    layer_uuid: str,
    unpremultiply: bool,
) -> Image.Image:
    image = reconstruct_layer(
        zip_file=zip_file,
        layer_uuid=layer_uuid,
        width=document.width,
        height=document.height,
        tile_size=document.tile_size,
        mode="RGBA",
    )
    image = apply_orientation(
        image=image,
        orientation=document.orientation,
        flipped_horizontally=document.flipped_horizontally,
        flipped_vertically=document.flipped_vertically,
    )
    if unpremultiply:
        image = unpremultiply_rgba(image)
    return image


def _build_mask_alpha(
    zip_file: zipfile.ZipFile,
    document: ProcreateDocumentMeta,
) -> Image.Image | None:
    if not document.mask_uuid:
        return None
    if not layer_has_chunks(zip_file, document.mask_uuid):
        return None
    mask_image = reconstruct_layer(
        zip_file=zip_file,
        layer_uuid=document.mask_uuid,
        width=document.width,
        height=document.height,
        tile_size=document.tile_size,
        mode="L",
    )
    mask_image = apply_orientation(
        image=mask_image,
        orientation=document.orientation,
        flipped_horizontally=document.flipped_horizontally,
        flipped_vertically=document.flipped_vertically,
    )
    mask_alpha = extract_mask_alpha(mask_image)
    min_alpha, max_alpha = mask_alpha.getextrema()
    if min_alpha == max_alpha:
        # Fully transparent or fully opaque mask has no useful effect.
        return None
    return mask_alpha


def _should_skip_or_fail_existing_output(
    output_path: Path,
    output: str,
    if_exists: ExistingOutputPolicy,
    emit_output: OutputEventCallback | None,
) -> bool:
    if if_exists == "overwrite" or not output_path.exists():
        return False

    if if_exists == "skip":
        if emit_output is not None:
            emit_output(output, "skipped", output_path, "already_exists")
        return True

    message = f"Output already exists: {output_path}"
    if emit_output is not None:
        emit_output(output, "failed", output_path, "already_exists")
    raise FileExistsError(message)


def convert_procreate_file(
    source_path: Path,
    output_dir: Path | None = None,
    write_psd: bool = True,
    write_flat_png: bool = False,
    write_flat_jpg: bool = False,
    write_animated_webp: bool = False,
    write_animated_gif: bool = False,
    write_timelapse_mp4: bool = False,
    apply_mask: bool = False,
    include_background: bool = True,
    unpremultiply: bool = True,
    jpg_quality: int = 95,
    if_exists: ExistingOutputPolicy = "overwrite",
    on_output_event: OutputEventCallback | None = None,
) -> ConversionResult:
    source_path = source_path.resolve()
    output_dir = (output_dir or source_path.parent).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    if not (
        write_psd
        or write_flat_png
        or write_flat_jpg
        or write_animated_webp
        or write_animated_gif
        or write_timelapse_mp4
    ):
        raise ValueError("No output format selected")
    if if_exists not in {"overwrite", "skip", "fail"}:
        raise ValueError(f"Unsupported if_exists policy: {if_exists}")

    with zipfile.ZipFile(source_path) as zip_file:
        def emit_output(
            output: str,
            status: str,
            path: Path | None = None,
            message: str | None = None,
        ) -> None:
            if on_output_event is None:
                return
            on_output_event(output, status, path, message)

        document = parse_document_archive(zip_file=zip_file, source_path=source_path)
        mask_alpha = _build_mask_alpha(zip_file, document) if apply_mask else None
        composite_preview = None

        layers: list[LayerImageData] = []
        frame_sources: list[tuple[ProcreateLayerMeta, Image.Image]] = []
        for layer_meta in document.content_layers:
            layer_image = _reconstruct_oriented_rgba(
                zip_file=zip_file,
                document=document,
                layer_uuid=layer_meta.uuid,
                unpremultiply=unpremultiply,
            )
            if mask_alpha is not None:
                layer_image = apply_document_mask(layer_image, mask_alpha)
            frame_sources.append((layer_meta, layer_image))
            layers.append(
                LayerImageData(
                    name=layer_meta.name or "Imported from Procreate",
                    image=layer_image,
                    opacity=layer_meta.opacity,
                    hidden=layer_meta.hidden,
                    blend=layer_meta.blend,
                )
            )

        if not layers:
            raise ValueError(f"No content layers found in {source_path}")

        canvas_width, canvas_height = layers[0].image.size
        if (
            include_background
            and not document.background_hidden
            and document.background_color_rgba is not None
        ):
            background = LayerImageData(
                name="Background Color",
                image=Image.new("RGBA", (canvas_width, canvas_height), document.background_color_rgba),
                opacity=1.0,
                hidden=False,
                blend=0,
            )
            layers.append(background)

        if document.composite_uuid and layer_has_chunks(zip_file, document.composite_uuid):
            composite_preview = _reconstruct_oriented_rgba(
                zip_file=zip_file,
                document=document,
                layer_uuid=document.composite_uuid,
                unpremultiply=unpremultiply,
            )
            if mask_alpha is not None:
                composite_preview = apply_document_mask(composite_preview, mask_alpha)

        flat_image = composite_preview if composite_preview is not None else _flatten_layers(
            layers=layers,
            width=canvas_width,
            height=canvas_height,
        )

        psd_path = None
        if write_psd:
            candidate_psd_path = output_dir / f"{source_path.stem}.psd"
            if _should_skip_or_fail_existing_output(candidate_psd_path, "psd", if_exists, on_output_event):
                candidate_psd_path = None
            if candidate_psd_path is not None:
                psd_path = candidate_psd_path
                emit_output("psd", "started", psd_path)
                try:
                    write_layered_psd(
                        layers=layers,
                        width=canvas_width,
                        height=canvas_height,
                        output_path=psd_path,
                        icc_profile=document.icc_data,
                        composite_image=flat_image,
                    )
                except Exception as exc:
                    emit_output("psd", "failed", psd_path, str(exc))
                    raise
                emit_output("psd", "completed", psd_path)

        png_path = None
        if write_flat_png:
            candidate_png_path = output_dir / f"{source_path.stem}.png"
            if _should_skip_or_fail_existing_output(candidate_png_path, "png", if_exists, on_output_event):
                candidate_png_path = None
            if candidate_png_path is not None:
                png_path = candidate_png_path
                emit_output("png", "started", png_path)
                try:
                    _write_png(
                        image=flat_image,
                        output_path=png_path,
                        dpi=document.dpi,
                        icc_profile=document.icc_data,
                    )
                except Exception as exc:
                    emit_output("png", "failed", png_path, str(exc))
                    raise
                emit_output("png", "completed", png_path)

        jpg_path = None
        if write_flat_jpg:
            candidate_jpg_path = output_dir / f"{source_path.stem}.jpg"
            matte = document.background_color_rgba[:3] if document.background_color_rgba else (255, 255, 255)
            if _should_skip_or_fail_existing_output(candidate_jpg_path, "jpg", if_exists, on_output_event):
                candidate_jpg_path = None
            if candidate_jpg_path is not None:
                jpg_path = candidate_jpg_path
                emit_output("jpg", "started", jpg_path)
                try:
                    _write_jpg(
                        image=flat_image,
                        output_path=jpg_path,
                        dpi=document.dpi,
                        icc_profile=document.icc_data,
                        quality=jpg_quality,
                        matte_rgb=matte,
                    )
                except Exception as exc:
                    emit_output("jpg", "failed", jpg_path, str(exc))
                    raise
                emit_output("jpg", "completed", jpg_path)

        webp_path = None
        gif_path = None
        if write_animated_webp or write_animated_gif:
            visible_frames, held_lengths = _compose_animation_frames(
                document=document,
                frame_sources=frame_sources,
                include_background=include_background,
            )

            if _is_animation_candidate(document, len(visible_frames)):
                ordered_frames, ordered_holds = _apply_playback_sequence(
                    visible_frames,
                    held_lengths,
                    playback_direction=document.playback_direction,
                    playback_mode=document.playback_mode,
                )
                durations_ms = _build_frame_durations_ms(document.frame_rate, ordered_holds)
                loop_forever = document.playback_mode != 3

                if write_animated_webp:
                    candidate_webp_path = output_dir / f"{source_path.stem}.webp"
                    if _should_skip_or_fail_existing_output(candidate_webp_path, "webp", if_exists, on_output_event):
                        candidate_webp_path = None
                    if candidate_webp_path is not None:
                        webp_path = candidate_webp_path
                        emit_output("webp", "started", webp_path)
                        try:
                            _write_animated_webp(
                                frames=ordered_frames,
                                durations_ms=durations_ms,
                                output_path=webp_path,
                                loop_forever=loop_forever,
                            )
                        except Exception as exc:
                            emit_output("webp", "failed", webp_path, str(exc))
                            raise
                        emit_output("webp", "completed", webp_path)
                if write_animated_gif:
                    candidate_gif_path = output_dir / f"{source_path.stem}.gif"
                    if _should_skip_or_fail_existing_output(candidate_gif_path, "gif", if_exists, on_output_event):
                        candidate_gif_path = None
                    if candidate_gif_path is not None:
                        gif_path = candidate_gif_path
                        emit_output("gif", "started", gif_path)
                        try:
                            _write_animated_gif(
                                frames=ordered_frames,
                                durations_ms=durations_ms,
                                output_path=gif_path,
                                loop_forever=loop_forever,
                            )
                        except Exception as exc:
                            emit_output("gif", "failed", gif_path, str(exc))
                            raise
                        emit_output("gif", "completed", gif_path)
            else:
                if write_animated_webp:
                    emit_output("webp", "skipped", None, "not_animated")
                if write_animated_gif:
                    emit_output("gif", "skipped", None, "not_animated")

        timelapse_mp4_path = None
        if write_timelapse_mp4:
            candidate_mp4_path = output_dir / f"{source_path.stem}.timelapse.mp4"
            if _should_skip_or_fail_existing_output(candidate_mp4_path, "mp4", if_exists, on_output_event):
                candidate_mp4_path = None
            if candidate_mp4_path is not None:
                timelapse_mp4_path = candidate_mp4_path
                emit_output("mp4", "started", timelapse_mp4_path)
                try:
                    wrote_video = stitch_timelapse_segments(
                        zip_file=zip_file,
                        output_path=timelapse_mp4_path,
                    )
                except Exception as exc:
                    emit_output("mp4", "failed", timelapse_mp4_path, str(exc))
                    raise
                if not wrote_video:
                    timelapse_mp4_path = None
                    emit_output("mp4", "skipped", None, "no_timelapse_segments")
                else:
                    emit_output("mp4", "completed", timelapse_mp4_path)

    return ConversionResult(
        source=source_path,
        psd_path=psd_path,
        png_path=png_path,
        jpg_path=jpg_path,
        webp_path=webp_path,
        gif_path=gif_path,
        timelapse_mp4_path=timelapse_mp4_path,
        width=canvas_width,
        height=canvas_height,
        layer_count=len(layers),
    )
