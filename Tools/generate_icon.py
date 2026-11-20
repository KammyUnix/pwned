#!/usr/bin/env python3
"""Draws the Pwned app icon and its in-app logo images.

The mark is a shield with a magnifier cut out of it: protection and
inspection in one shape. It is drawn with supersampling so the edges are
clean at 1024 px. Run from the repository root:

    python3 Tools/generate_icon.py

Outputs go to Resources/Assets.xcassets and docs/icon.png. Needs Pillow and NumPy.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Resources" / "Assets.xcassets"

SIZE = 1024
SCALE = 4  # supersampling factor for the shapes
BIG = SIZE * SCALE


def bezier(p0, p1, p2, p3, steps=80):
    points = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        points.append((x, y))
    return points


def shield_outline():
    """A shield with rounded top corners, a slightly arched top and a rounded tip.

    Drawn in 1024 px space, then grown about the centre so the mark fills the tile.
    """
    left, right, mid = 262, 762, 512
    corner_y, top_y, side_y, tip_y = 292, 236, 548, 838
    radius = 62
    path = [(left, side_y), (left, corner_y)]
    path += bezier((left, corner_y), (left, corner_y - 34), (left + 24, top_y + 10), (left + radius, top_y + 6))
    path += bezier((left + radius, top_y + 6), (left + radius + 130, top_y - 4), (right - radius - 130, top_y - 4), (right - radius, top_y + 6))
    path += bezier((right - radius, top_y + 6), (right - 24, top_y + 10), (right, corner_y - 34), (right, corner_y))
    path += [(right, side_y)]
    path += bezier((right, side_y), (right, 706), (644, 786), (mid, tip_y))
    path += bezier((mid, tip_y), (380, 786), (left, 706), (left, side_y))
    grow = 1.16
    return [(512 + (x - 512) * grow, 500 + (y - 540) * grow) for x, y in path]


def scaled(points):
    return [(x * SCALE, y * SCALE) for x, y in points]


def draw_mark_mask():
    """White where the mark is solid. The lens is cut out of the shield."""
    mask = Image.new("L", (BIG, BIG), 0)
    d = ImageDraw.Draw(mask)
    d.polygon(scaled(shield_outline()), fill=255)

    cx, cy = 482, 452
    outer, inner = 190, 134
    # Lens ring.
    d.ellipse([(cx - outer) * SCALE, (cy - outer) * SCALE, (cx + outer) * SCALE, (cy + outer) * SCALE], fill=0)
    d.ellipse([(cx - inner) * SCALE, (cy - inner) * SCALE, (cx + inner) * SCALE, (cy + inner) * SCALE], fill=255)

    # Handle, at 45 degrees, ending inside the shield.
    import math

    angle = math.radians(45)
    start = outer - 16
    end = outer + 118
    x0, y0 = cx + start * math.cos(angle), cy + start * math.sin(angle)
    x1, y1 = cx + end * math.cos(angle), cy + end * math.sin(angle)
    width = 62
    d.line([(x0 * SCALE, y0 * SCALE), (x1 * SCALE, y1 * SCALE)], fill=0, width=width * SCALE)
    for x, y in ((x0, y0), (x1, y1)):
        r = width / 2
        d.ellipse([(x - r) * SCALE, (y - r) * SCALE, (x + r) * SCALE, (y + r) * SCALE], fill=0)
    return mask.resize((SIZE, SIZE), Image.LANCZOS)


def gradient(top, bottom, highlight):
    """Vertical neutral gradient with a soft light from the upper left."""
    y = np.linspace(0, 1, SIZE)[:, None]
    base = np.array(top)[None, None, :] * (1 - y[..., None]) + np.array(bottom)[None, None, :] * y[..., None]
    base = np.broadcast_to(base, (SIZE, SIZE, 3)).copy()

    xx, yy = np.meshgrid(np.linspace(0, 1, SIZE), np.linspace(0, 1, SIZE))
    distance = np.sqrt((xx - 0.2) ** 2 + (yy - 0.05) ** 2)
    glow = np.clip(1 - distance / 0.95, 0, 1) ** 2.2 * highlight
    base += glow[..., None] * 255
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")


def glass_rim(image, strength):
    """A faint light edge and a soft sheen across the upper half."""
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    # Sheen: a wide ellipse centred above the tile, blurred to a soft wash.
    d.ellipse([-260, -760, SIZE + 260, 420], fill=(255, 255, 255, int(255 * strength)))
    overlay = overlay.filter(ImageFilter.GaussianBlur(60))
    out = Image.alpha_composite(image.convert("RGBA"), overlay)

    rim = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle([3, 3, SIZE - 4, SIZE - 4], radius=224, outline=(255, 255, 255, int(255 * strength * 1.4)), width=3)
    return Image.alpha_composite(out, rim).convert("RGB")


def compose(top, bottom, highlight, sheen, mark=(255, 255, 255), shadow=0.30):
    background = gradient(top, bottom, highlight)
    background = glass_rim(background, sheen)
    mask = draw_mark_mask()

    # Soft shadow under the mark gives it depth without a glow.
    shadow_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_mask = ImageChops.offset(mask, 0, 14).filter(ImageFilter.GaussianBlur(22))
    shadow_layer.putalpha(shadow_mask.point(lambda v: int(v * shadow)))
    composed = Image.alpha_composite(background.convert("RGBA"), shadow_layer)

    glyph = Image.new("RGBA", (SIZE, SIZE), mark + (255,))
    glyph.putalpha(mask)
    return Image.alpha_composite(composed, glyph).convert("RGB")


VARIANTS = {
    # name: (top, bottom, highlight strength, sheen strength)
    "Slate": ((116, 119, 125), (70, 72, 77), 0.10, 0.10),
    "Graphite": ((58, 59, 63), (28, 29, 32), 0.07, 0.07),
    "Silver": ((172, 175, 181), (124, 127, 134), 0.12, 0.12),
}


def write_icon_set(folder, image, contents):
    folder.mkdir(parents=True, exist_ok=True)
    for name, picture in image.items():
        picture.save(folder / name, optimize=True)
    (folder / "Contents.json").write_text(contents)


def single(filename):
    return {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}


def contents_json(images):
    import json

    return json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n"


def main():
    slate = compose(*VARIANTS["Slate"][:2], VARIANTS["Slate"][2], VARIANTS["Slate"][3])
    graphite = compose(*VARIANTS["Graphite"][:2], VARIANTS["Graphite"][2], VARIANTS["Graphite"][3])
    silver = compose(*VARIANTS["Silver"][:2], VARIANTS["Silver"][2], VARIANTS["Silver"][3], shadow=0.22)

    # The tinted appearance is grayscale; iOS maps its luminance to the user's tint.
    tinted = compose((24, 24, 24), (6, 6, 6), 0.05, 0.04, shadow=0.0).convert("L").convert("RGB")

    write_icon_set(
        ASSETS / "AppIcon.appiconset",
        {"AppIcon.png": slate, "AppIcon-Dark.png": graphite, "AppIcon-Tinted.png": tinted},
        contents_json(
            [
                single("AppIcon.png"),
                {**single("AppIcon-Dark.png"), "appearances": [{"appearance": "luminosity", "value": "dark"}]},
                {**single("AppIcon-Tinted.png"), "appearances": [{"appearance": "luminosity", "value": "tinted"}]},
            ]
        ),
    )
    write_icon_set(ASSETS / "AppIconGraphite.appiconset", {"AppIconGraphite.png": graphite}, contents_json([single("AppIconGraphite.png")]))
    write_icon_set(ASSETS / "AppIconSilver.appiconset", {"AppIconSilver.png": silver}, contents_json([single("AppIconSilver.png")]))

    # In-app copies, shown on the Info page and in Settings.
    for name, picture in (("AppLogo", slate), ("AppLogoGraphite", graphite), ("AppLogoSilver", silver)):
        small = picture.resize((512, 512), Image.LANCZOS)
        write_icon_set(
            ASSETS / f"{name}.imageset",
            {f"{name}.png": small},
            contents_json([{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}]),
        )

    docs = ROOT / "docs"
    docs.mkdir(exist_ok=True)
    slate.resize((256, 256), Image.LANCZOS).save(docs / "icon.png", optimize=True)
    print("Icon written.")


if __name__ == "__main__":
    main()
