#!/usr/bin/env python3
"""Render the two Connect IQ Store icons from the shared trefoil geometry."""

from pathlib import Path
from PIL import Image, ImageCms, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "store-assets"
YELLOW = "#FFD43B"
BLACK = "#111111"
SRGB_PROFILE = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()


def render(size: int, filename: str) -> None:
    scale = 4
    canvas = size * scale
    factor = canvas / 500.0
    image = Image.new("RGB", (canvas, canvas), YELLOW)
    draw = ImageDraw.Draw(image)

    def box(radius: float) -> tuple[float, float, float, float]:
        center = 250 * factor
        scaled = radius * factor
        return (center - scaled, center - scaled, center + scaled, center + scaled)

    draw.ellipse(box(198), outline=BLACK, width=round(18 * factor))
    for start in (-120, 0, 120):
        draw.pieslice(box(150), start=start, end=start + 60, fill=BLACK)
    draw.ellipse(box(55), fill=YELLOW)
    draw.ellipse(box(31), fill=BLACK)

    image.resize((size, size), Image.Resampling.LANCZOS).save(
        OUTPUT / filename, format="PNG", optimize=True, icc_profile=SRGB_PROFILE
    )


render(500, "store-icon.png")
render(128, "on-device-store-icon.png")
