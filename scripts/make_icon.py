#!/usr/bin/env python3
"""Generate macOS AppIcon assets into Sources/Resources/Assets.xcassets/AppIcon.appiconset."""
import argparse
import math
import os
from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(
    ROOT_DIR, "Sources", "Resources", "Assets.xcassets", "AppIcon.appiconset"
)

ICON_SLOTS = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def build_squircle_mask(size: int, radius: int) -> Image.Image:
    scale = 4
    mw, mh = size * scale, size * scale
    mask_hr = Image.new("L", (mw, mh), 0)
    draw = ImageDraw.Draw(mask_hr)
    draw.rounded_rectangle([0, 0, mw, mh], radius=radius * scale, fill=255)
    return mask_hr.resize((size, size), Image.LANCZOS)


def apply_drop_shadow(card: Image.Image) -> Image.Image:
    w, h = 1024, 1024
    master = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    shadow_mask = Image.new("L", (w, h), 0)
    shadow_mask.paste(card.split()[3], (100, 112))
    shadow_blurred = shadow_mask.filter(ImageFilter.GaussianBlur(radius=16))

    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    s_px = shadow_blurred.load()
    for y in range(h):
        for x in range(w):
            alpha = s_px[x, y]
            if alpha > 0:
                shadow.putpixel((x, y), (0, 0, 0, int(alpha * 0.24)))

    master = Image.alpha_composite(master, shadow)
    master.paste(card, (100, 100), card)
    return master


def build_geometric_icon() -> Image.Image:
    """Programmatically draw an original macOS obsidian terminal icon at 4x supersampling."""
    cw, ch = 824, 824
    s = 4
    w, h = cw * s, ch * s

    # Deep obsidian vertical gradient (#14161B -> #1E222B)
    bg = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    px = bg.load()
    top_rgb = (20, 22, 27)
    bot_rgb = (30, 34, 43)
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top_rgb[0] + (bot_rgb[0] - top_rgb[0]) * t)
        g = int(top_rgb[1] + (bot_rgb[1] - top_rgb[1]) * t)
        b = int(top_rgb[2] + (bot_rgb[2] - top_rgb[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)

    # Subtle radial warm glow behind the prompt
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g_draw = ImageDraw.Draw(glow)
    cx, cy = int(w * 0.48), int(h * 0.48)
    for step in range(28, 0, -1):
        rad = int(w * 0.42 * (step / 28.0))
        alpha = int(16 * (1.0 - step / 29.0) ** 1.4)
        g_draw.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=(245, 166, 92, alpha))
    bg = Image.alpha_composite(bg, glow)

    # Crisp vector terminal prompt '>' and cursor '_'
    fg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(fg)

    stroke_w = int(68 * s)
    # '>' chevron points
    p1 = (int(w * 0.25), int(h * 0.34))
    p2 = (int(w * 0.46), int(h * 0.50))
    p3 = (int(w * 0.25), int(h * 0.66))
    amber = (245, 173, 98, 255)
    cream = (242, 240, 234, 255)

    draw.line([p1, p2], fill=amber, width=stroke_w, joint="curve")
    draw.line([p2, p3], fill=amber, width=stroke_w, joint="curve")
    r_cap = stroke_w // 2
    for pt in (p1, p2, p3):
        draw.ellipse([pt[0] - r_cap, pt[1] - r_cap, pt[0] + r_cap, pt[1] + r_cap], fill=amber)

    # '_' cursor bar
    bar_x0 = int(w * 0.52)
    bar_x1 = int(w * 0.76)
    bar_y0 = int(h * 0.62)
    bar_y1 = bar_y0 + stroke_w
    draw.rounded_rectangle([bar_x0, bar_y0, bar_x1, bar_y1], radius=stroke_w // 2, fill=cream)

    # Subtle inner glass rim highlight
    draw.rounded_rectangle(
        [int(6 * s), int(6 * s), w - int(6 * s), h - int(6 * s)],
        radius=180 * s,
        outline=(255, 255, 255, 34),
        width=int(4 * s),
    )

    combined = Image.alpha_composite(bg, fg).resize((cw, ch), Image.LANCZOS)
    combined.putalpha(build_squircle_mask(cw, 185))
    return apply_drop_shadow(combined)


def build_icon(source_path: str) -> Image.Image:
    src = Image.open(source_path).convert("RGBA")
    cw, ch = 824, 824
    card = src.resize((cw, ch), Image.LANCZOS)
    card.putalpha(build_squircle_mask(cw, 185))
    return apply_drop_shadow(card)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate siqi AppIcon set")
    parser.add_argument(
        "source",
        nargs="?",
        default=None,
        help="Optional path to source 1024x1024+ artwork image; omits to render geometric icon",
    )
    args = parser.parse_args()

    if args.source:
        if not os.path.exists(args.source):
            raise SystemExit(f"Source artwork not found: {args.source}")
        master_icon = build_icon(args.source)
    else:
        master_icon = build_geometric_icon()

    os.makedirs(OUT_DIR, exist_ok=True)
    for name, size in ICON_SLOTS.items():
        master_icon.resize((size, size), Image.LANCZOS).save(os.path.join(OUT_DIR, name))
    print(f"Generated {len(ICON_SLOTS)} icon slots in {OUT_DIR}")


if __name__ == "__main__":
    main()
