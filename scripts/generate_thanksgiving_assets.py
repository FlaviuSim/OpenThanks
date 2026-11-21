#!/usr/bin/env python3
"""Draw Thanksgiving-week artwork in the Jonny #05 palette.

Flat, geometric decals (not clip art) for the seasonal theme, plus the
alternate app icon. Output is deterministic. Run from the repo root:

    .venv/bin/python scripts/generate_thanksgiving_assets.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "OpenThanks" / "Assets.xcassets"
ICONS = ROOT / "OpenThanks" / "AlternateIcons"
APP_ICON = ASSETS / "AppIcon.appiconset" / "AppIcon.png"

ORANGE = (246, 86, 1, 255)
DEEP = (204, 71, 1, 255)
SOFT = (250, 162, 115, 255)
TINT = (254, 228, 214, 255)
INK = (44, 15, 0, 255)
CREAM = (255, 245, 238, 255)
GOLD = (232, 160, 90, 255)
BROWN = (122, 52, 18, 255)
WHITE = (255, 255, 255, 255)

# Maple leaf, tip up, in a 0–100 box. Lobes stay broad so it does not read as a star.
MAPLE = [
    (50, 6),
    (57, 20),
    (69, 12),
    (65, 28),
    (80, 24),
    (70, 38),
    (84, 48),
    (66, 50),
    (72, 66),
    (56, 60),
    (52, 86),
    (50, 68),
    (48, 86),
    (44, 60),
    (28, 66),
    (34, 50),
    (16, 48),
    (30, 38),
    (20, 24),
    (35, 28),
    (31, 12),
    (43, 20),
]


def chaikin(points, iterations=2):
    pts = list(points)
    for _ in range(iterations):
        nxt = []
        count = len(pts)
        for i in range(count):
            p0 = pts[i]
            p1 = pts[(i + 1) % count]
            nxt.append((0.75 * p0[0] + 0.25 * p1[0], 0.75 * p0[1] + 0.25 * p1[1]))
            nxt.append((0.25 * p0[0] + 0.75 * p1[0], 0.25 * p0[1] + 0.75 * p1[1]))
        pts = nxt
    return pts


def maple_points(cx, cy, extent, rotation_deg):
    """`extent` is the leaf's half-width in pixels."""
    rad = math.radians(rotation_deg)
    cos_r, sin_r = math.cos(rad), math.sin(rad)
    unit = extent / 50
    points = []
    for x, y in chaikin(MAPLE, 2):
        px = (x - 50) * unit
        py = (y - 50) * unit
        rx = px * cos_r - py * sin_r
        ry = px * sin_r + py * cos_r
        points.append((cx + rx, cy + ry))
    return points


def heart_points(cx, cy, scale, n=96):
    points = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        points.append((cx + x * scale / 17, cy + y * scale / 17))
    return points


def new_canvas(size):
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def paste_center(base, sprite, center):
    x = int(round(center[0] - sprite.size[0] / 2))
    y = int(round(center[1] - sprite.size[1] / 2))
    base.alpha_composite(sprite, (x, y))


def rotated_ellipse(size, fill, angle, inner=None):
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse([0, 0, size[0] - 1, size[1] - 1], fill=fill)
    if inner:
        inset, inner_fill = inner
        draw.ellipse(
            [inset, inset, size[0] - 1 - inset, size[1] - 1 - inset],
            fill=inner_fill,
        )
    return image.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)


def halo(image, radius, color=CREAM):
    if radius <= 0:
        return image
    alpha = image.getchannel("A")
    dilated = alpha.filter(ImageFilter.MaxFilter(radius * 2 + 1))
    plate = Image.new("RGBA", image.size, color)
    plate.putalpha(dilated)
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    out.alpha_composite(plate)
    out.alpha_composite(image)
    return out


def downsample(image, size):
    return image.resize(size, Image.Resampling.LANCZOS)


def draw_leaf(size, fill, vein, rotation=0, scale=0.42):
    image = new_canvas(size)
    draw = ImageDraw.Draw(image)
    extent = size * scale
    points = maple_points(size / 2, size / 2, extent, rotation)
    draw.polygon(points, fill=fill)
    cx, cy = size / 2, size / 2
    rad = math.radians(rotation)
    tip = (cx + math.sin(rad) * extent * 0.55, cy - math.cos(rad) * extent * 0.62)
    stem = (cx - math.sin(rad) * extent * 0.02, cy + math.cos(rad) * extent * 0.48)
    if vein is not None:
        draw.line([stem, tip], fill=vein, width=max(2, int(extent * 0.03)))
    return image


def tapered_feather(length, width, fill, vein=None):
    image = Image.new("RGBA", (width, length), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    cx = width / 2
    raw = [
        (cx, 2),
        (cx + width * 0.46, length * 0.42),
        (cx + width * 0.14, length - 2),
        (cx - width * 0.14, length - 2),
        (cx - width * 0.46, length * 0.42),
    ]
    draw.polygon(chaikin(raw, 3), fill=fill)
    if vein is not None:
        draw.line(
            [(cx, length * 0.18), (cx, length * 0.88)],
            fill=vein,
            width=max(2, width // 12),
        )
    return image


def draw_turkey(size):
    image = new_canvas(size)
    cx, cy = size * 0.46, size * 0.64
    colors = [BROWN, DEEP, GOLD, ORANGE, SOFT, ORANGE, DEEP]
    count = len(colors)
    for i, color in enumerate(colors):
        angle = 225 + i * (90 / (count - 1))
        rad = math.radians(angle)
        feather = tapered_feather(int(size * 0.40), int(size * 0.11), color)
        rotated = feather.rotate(270 - angle, resample=Image.Resampling.BICUBIC, expand=True)
        dist = size * 0.18
        paste_center(image, rotated, (cx + math.cos(rad) * dist, cy + math.sin(rad) * dist))

    draw = ImageDraw.Draw(image)
    body_r = size * 0.20
    draw.ellipse(
        [cx - body_r, cy - body_r * 0.85, cx + body_r, cy + body_r],
        fill=BROWN,
    )
    belly = size * 0.125
    draw.ellipse(
        [cx - belly, cy - belly * 0.2, cx + belly, cy + belly * 1.15],
        fill=ORANGE,
    )
    heart = heart_points(cx, cy + size * 0.04, size * 0.11)
    draw.polygon(heart, fill=CREAM)

    # Head, slightly to the right, in front of the fan.
    head_c = (cx + size * 0.18, cy - size * 0.16)
    head_r = size * 0.075
    draw.ellipse(
        [
            head_c[0] - head_r,
            head_c[1] - head_r,
            head_c[0] + head_r,
            head_c[1] + head_r,
        ],
        fill=BROWN,
    )
    beak = [
        (head_c[0] + head_r * 0.4, head_c[1] - head_r * 0.15),
        (head_c[0] + head_r * 1.7, head_c[1] + head_r * 0.15),
        (head_c[0] + head_r * 0.35, head_c[1] + head_r * 0.45),
    ]
    draw.polygon(beak, fill=GOLD)
    wattle_r = size * 0.022
    draw.ellipse(
        [
            head_c[0] + head_r * 0.15 - wattle_r,
            head_c[1] + head_r * 0.35,
            head_c[0] + head_r * 0.15 + wattle_r,
            head_c[1] + head_r * 0.35 + wattle_r * 2.4,
        ],
        fill=DEEP,
    )
    eye_r = max(2, int(size * 0.012))
    eye = (head_c[0] + head_r * 0.15, head_c[1] - head_r * 0.15)
    draw.ellipse(
        [eye[0] - eye_r, eye[1] - eye_r, eye[0] + eye_r, eye[1] + eye_r],
        fill=INK,
    )
    return image


def draw_pie(size):
    image = new_canvas(size)
    draw = ImageDraw.Draw(image)
    cx = cy = size / 2
    outer = size * 0.36
    draw.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], fill=GOLD)
    inner = size * 0.28
    draw.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=DEEP)
    # Crimp.
    crimp_r = size * 0.028
    count = 18
    for i in range(count):
        ang = 2 * math.pi * i / count
        px = cx + math.cos(ang) * (outer - crimp_r * 0.2)
        py = cy + math.sin(ang) * (outer - crimp_r * 0.2)
        draw.ellipse(
            [px - crimp_r, py - crimp_r, px + crimp_r, py + crimp_r],
            fill=TINT,
        )
    # Vents.
    for dx, tilt in ((-size * 0.09, -0.18), (0, 0.0), (size * 0.09, 0.18)):
        top = (cx + dx, cy - size * 0.08)
        bottom = (cx + dx + tilt * size * 0.12, cy + size * 0.05)
        draw.line([top, bottom], fill=GOLD, width=max(3, size // 70))
    heart = heart_points(cx, cy + size * 0.01, size * 0.07)
    draw.polygon(heart, fill=CREAM)
    return image


def draw_wheat(size):
    image = new_canvas(size)
    draw = ImageDraw.Draw(image)
    cx = size * 0.50
    base = size * 0.84
    stalks = [
        (cx - size * 0.12, -8, BROWN),
        (cx, 0, GOLD),
        (cx + size * 0.12, 8, DEEP),
    ]
    for sx, lean, color in stalks:
        top = size * 0.16
        draw.line([(sx, base), (sx + lean, top)], fill=color, width=max(3, size // 40))
        steps = 7
        for i in range(steps):
            t = i / (steps - 1)
            y = top + (base - size * 0.18 - top) * t
            x = sx + lean * (1 - t) * 0.3
            grain_w = size * 0.045
            grain_h = size * 0.07
            for side in (-1, 1):
                ellipse = rotated_ellipse(
                    (int(grain_w * 2), int(grain_h * 2)),
                    color if i % 2 == 0 else ORANGE,
                    side * 28,
                )
                paste_center(image, ellipse, (x + side * grain_w * 1.3, y))
    return image


def draw_heart_mark(size):
    image = new_canvas(size)
    draw = ImageDraw.Draw(image)
    draw.polygon(heart_points(size * 0.46, size * 0.50, size * 0.34), fill=ORANGE)
    leaf = draw_leaf(int(size * 0.46), DEEP, CREAM, rotation=-28, scale=0.40)
    paste_center(image, leaf, (size * 0.70, size * 0.34))
    return image


def draw_leaves(size):
    image = new_canvas(size)
    specs = [
        (0.40, 0.62, 22, ORANGE, DEEP),
        (0.66, 0.40, -32, DEEP, GOLD),
        (0.42, 0.34, -8, GOLD, BROWN),
    ]
    for x, y, rotation, fill, vein in specs:
        leaf = draw_leaf(int(size * 0.62), fill, vein, rotation=rotation, scale=0.40)
        paste_center(image, leaf, (size * x, size * y))
    return image


def draw_success(width, height):
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    turkey = halo(draw_turkey(int(height * 0.92)), radius=max(6, height // 80))
    leaves = halo(draw_leaves(int(height * 0.78)), radius=max(5, height // 90))
    pie = halo(draw_pie(int(height * 0.70)), radius=max(5, height // 90))
    paste_center(image, leaves, (width * 0.18, height * 0.54))
    paste_center(image, pie, (width * 0.82, height * 0.56))
    paste_center(image, turkey, (width * 0.50, height * 0.52))
    return image


def finish_decal(image, out_size, rim=18):
    plated = halo(image, radius=rim)
    return downsample(plated, (out_size, out_size))


def imageset(name, image):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png", optimize=True)
    (folder / "Contents.json").write_text(
        """{
  "images" : [
    {
      "filename" : "%s.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "original"
  }
}
"""
        % name,
        encoding="utf-8",
    )


def white_leaf(size, rotation):
    return draw_leaf(size, WHITE, None, rotation=rotation, scale=0.42)


def feather_fan(size):
    image = new_canvas(size)
    for angle in (246, 270, 294):
        feather = tapered_feather(int(size * 0.70), int(size * 0.20), WHITE)
        rotated = feather.rotate(270 - angle, resample=Image.Resampling.BICUBIC, expand=True)
        rad = math.radians(angle)
        paste_center(
            image,
            rotated,
            (size * 0.50 + math.cos(rad) * size * 0.12, size * 0.58 + math.sin(rad) * size * 0.16),
        )
    return image


def thanksgiving_icon(source_1024):
    icon = source_1024.convert("RGBA")
    fan = feather_fan(320)
    paste_center(icon, fan, (512, 132))
    for center, rotation in (((210, 790), 28), ((814, 790), -28)):
        leaf = white_leaf(250, rotation)
        paste_center(icon, leaf, center)
    # Stay inside the orange field: knock out anything that covered the heart.
    # The source heart and ring are white; re-stamp the original white pixels
    # so the heart-O itself is unchanged.
    original = source_1024.convert("RGBA")
    src = list(original.getdata())
    out = list(icon.getdata())
    for i, pixel in enumerate(src):
        if pixel[0] > 245 and pixel[1] > 245 and pixel[2] > 245:
            out[i] = (255, 255, 255, 255)
    icon.putdata(out)
    rgb = Image.new("RGB", icon.size, (246, 86, 1))
    rgb.paste(icon, mask=icon.getchannel("A"))
    return rgb


def write_icons(icon_1024):
    ICONS.mkdir(parents=True, exist_ok=True)
    sizes = {
        "AppIcon-Thanksgiving.png": (1024, 1024),
        "AppIcon-Thanksgiving@2x.png": (120, 120),
        "AppIcon-Thanksgiving@3x.png": (180, 180),
        "AppIcon-Thanksgiving@2x~ipad.png": (152, 152),
        "AppIcon-Thanksgiving@3x~ipad.png": (167, 167),
        "AppIcon-Thanksgiving-Preview.png": (180, 180),
    }
    for name, size in sizes.items():
        image = icon_1024 if size == (1024, 1024) else icon_1024.resize(size, Image.Resampling.LANCZOS)
        image.save(ICONS / name, optimize=True)


def main():
    scale = 3
    big = 512 * scale
    imageset("ThanksgivingTurkey", finish_decal(draw_turkey(big), 512, rim=28))
    imageset("ThanksgivingLeaf", finish_decal(draw_leaf(big, ORANGE, DEEP, rotation=-18), 512, rim=26))
    imageset("ThanksgivingLeaves", finish_decal(draw_leaves(big), 512, rim=22))
    imageset("ThanksgivingPie", finish_decal(draw_pie(big), 512, rim=26))
    imageset("ThanksgivingHeart", finish_decal(draw_heart_mark(big), 512, rim=26))
    imageset("ThanksgivingWheat", finish_decal(draw_wheat(big), 512, rim=22))
    success = draw_success(1400 * 2, 800 * 2)
    imageset_wide("ThanksgivingSuccess", downsample(success, (1400, 800)))
    source = Image.open(APP_ICON)
    write_icons(thanksgiving_icon(source))
    print("wrote thanksgiving assets")


def imageset_wide(name, image):
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}.png", optimize=True)
    (folder / "Contents.json").write_text(
        """{
  "images" : [
    {
      "filename" : "%s.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "template-rendering-intent" : "original"
  }
}
"""
        % name,
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
