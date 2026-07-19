#!/usr/bin/env python3
"""Regenerate OpenThanks App Store icons + marketing screenshots.

Requires: python3 -m pip install pillow
Run from repo root: python3 scripts/generate_appstore_assets.py
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ICON_DIR = ROOT / "OpenThanks/Assets.xcassets/AppIcon.appiconset"
STORE = ROOT / "AppStore"
SHOTS_67 = STORE / "Screenshots/iPhone-6.7-inch"
SHOTS_65 = STORE / "Screenshots/iPhone-6.5-inch"

CORAL = (224, 122, 95)
CORAL_LIGHT = (244, 151, 127)
CORAL_PALE = (249, 195, 169)
CREAM = (247, 245, 242)
TEXT = (26, 26, 27)
TEXT_SEC = (92, 92, 98)


def load_font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
        if bold
        else "/System/Library/Fonts/Supplemental/Georgia.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
        if bold
        else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def heart_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    cx = cy = size / 2
    cy -= size * 0.03
    scale = size * 0.0192
    pts = []
    for i in range(360):
        t = math.radians(i)
        x = 16 * math.sin(t) ** 3
        y = -(
            13 * math.cos(t)
            - 5 * math.cos(2 * t)
            - 2 * math.cos(3 * t)
            - math.cos(4 * t)
        )
        pts.append((cx + x * scale, cy + y * scale))
    draw.polygon(pts, fill=255)
    return mask.filter(ImageFilter.GaussianBlur(0.8))


def make_icon(bg: tuple[int, int, int], *, white: bool = False) -> Image.Image:
    size = 1024
    base = Image.new("RGB", (size, size), bg)
    px = base.load()
    cx = cy = size / 2
    max_d = size * 0.55
    for y in range(size):
        for x in range(size):
            d = min(math.hypot(x - cx, y - cy) / max_d, 1.0)
            lift = int(28 * (1 - d) * (1 - d))
            px[x, y] = (
                min(255, bg[0] + lift),
                min(255, bg[1] + int(lift * 0.7)),
                min(255, bg[2] + int(lift * 0.5)),
            )

    if white:
        fill = Image.new("RGB", (size, size), (255, 255, 255))
    else:
        fill = Image.new("RGB", (size, size))
        fp = fill.load()
        for y in range(size):
            t = y / (size - 1)
            if t < 0.45:
                u = t / 0.45
                color = tuple(
                    int(CORAL_PALE[i] * (1 - u) + CORAL_LIGHT[i] * u) for i in range(3)
                )
            else:
                u = (t - 0.45) / 0.55
                color = tuple(
                    int(CORAL_LIGHT[i] * (1 - u) + CORAL[i] * u) for i in range(3)
                )
            for x in range(size):
                fp[x, y] = color

    mask = heart_mask(size)
    margin = int(size * 0.19)
    inner = size - margin * 2
    fill_r = fill.resize((inner, inner), Image.Resampling.LANCZOS)
    mask_r = mask.resize((inner, inner), Image.Resampling.LANCZOS)

    if not white:
        glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        for i in range(50, 0, -1):
            a = int(12 * (i / 50.0))
            pad = margin - int((50 - i) * 1.2)
            gd.ellipse(
                [pad, pad + 20, size - pad, size - pad + 40],
                fill=(*CORAL_PALE, a),
            )
        glow = glow.filter(ImageFilter.GaussianBlur(40))
        base = Image.alpha_composite(base.convert("RGBA"), glow).convert("RGB")

    base.paste(fill_r, (margin, margin - 8), mask_r)
    return base


def make_heart_layer(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grad)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(int(CORAL_PALE[i] * (1 - t) + CORAL[i] * t) for i in range(3))
        gdraw.line([(0, y), (size, y)], fill=(*color, 255))
    mask = heart_mask(size)
    heart = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    heart.paste(grad, (0, 0), mask)
    return heart


def phone_frame(content: Image.Image) -> Image.Image:
    w, h = 1290, 2796
    frame = Image.new("RGB", (w, h), CREAM)
    d = ImageDraw.Draw(frame)
    for y in range(0, 520):
        t = y / 520
        color = tuple(int(CREAM[i] * (1 - 0.2 * t) + CORAL_PALE[i] * 0.2 * t) for i in range(3))
        d.line([(0, y), (w, y)], fill=color)

    pad_x, pad_top, pad_bot = 90, 620, 80
    phone_w = w - pad_x * 2
    phone_h = h - pad_top - pad_bot
    phone = Image.new("RGB", (phone_w, phone_h), (22, 22, 24))
    inset = 14
    screen = content.resize(
        (phone_w - inset * 2, phone_h - inset * 2), Image.Resampling.LANCZOS
    )
    phone.paste(screen, (inset, inset))
    mask = Image.new("L", (phone_w, phone_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, phone_w - 1, phone_h - 1], radius=70, fill=255
    )
    frame.paste(phone, (pad_x, pad_top), mask)
    nx0 = w // 2 - 90
    d.rounded_rectangle(
        [nx0, pad_top + 22, nx0 + 180, pad_top + 48], radius=16, fill=(10, 10, 11)
    )
    return frame


def mock_feed(title: str, lines: list[str]) -> Image.Image:
    screen = Image.new("RGB", (900, 1800), CREAM)
    d = ImageDraw.Draw(screen)
    d.text((40, 70), "OpenThanks", font=load_font(44, bold=True), fill=TEXT)
    d.rounded_rectangle([560, 65, 860, 125], radius=28, fill=CORAL)
    d.text((590, 78), "Thank someone", font=load_font(22, bold=True), fill=(43, 18, 9))
    d.rounded_rectangle([40, 160, 200, 220], radius=14, fill=(240, 237, 232))
    d.text((70, 172), "World", font=load_font(26, bold=True), fill=TEXT)
    d.text((230, 172), "Personal", font=load_font(26), fill=TEXT_SEC)
    d.rounded_rectangle([40, 260, 860, 720], radius=28, fill=(255, 255, 255))
    d.ellipse([70, 300, 150, 380], fill=CORAL_PALE)
    d.text((175, 310), title, font=load_font(28, bold=True), fill=TEXT)
    d.text((175, 350), "thanked Alex", font=load_font(24), fill=TEXT_SEC)
    y = 420
    for line in lines:
        if line:
            d.text((70, y), line, font=load_font(28), fill=TEXT)
        y += 42
    d.text((70, 640), "♡  12", font=load_font(26), fill=CORAL)
    d.rounded_rectangle([40, 760, 860, 1100], radius=28, fill=(255, 255, 255))
    d.ellipse([70, 800, 150, 880], fill=(230, 220, 210))
    d.text((175, 820), "Jordan thanked Sam", font=load_font(26, bold=True), fill=TEXT)
    d.text(
        (70, 920),
        "You made our launch week unforgettable.",
        font=load_font(26),
        fill=TEXT_SEC,
    )
    return screen


def mock_compose() -> Image.Image:
    screen = Image.new("RGB", (900, 1800), CREAM)
    d = ImageDraw.Draw(screen)
    d.text((40, 70), "Share appreciation", font=load_font(40, bold=True), fill=TEXT)
    d.text((40, 180), "To", font=load_font(22), fill=TEXT_SEC)
    d.rounded_rectangle([40, 220, 860, 300], radius=16, fill=(255, 255, 255))
    d.text((60, 242), "maya@example.com", font=load_font(26), fill=TEXT)
    d.text((40, 340), "Your message", font=load_font(22), fill=TEXT_SEC)
    d.rounded_rectangle([40, 380, 860, 780], radius=16, fill=(255, 255, 255))
    for i, line in enumerate(
        [
            "Maya — your calm under pressure",
            "this week carried the whole team.",
            "Thank you for leading with kindness.",
        ]
    ):
        d.text((60, 420 + i * 44), line, font=load_font(28), fill=TEXT)
    d.rounded_rectangle([40, 820, 860, 980], radius=20, fill=(255, 255, 255))
    d.text((70, 870), "Add a photo", font=load_font(28, bold=True), fill=CORAL)
    d.rounded_rectangle([40, 1520, 860, 1640], radius=40, fill=CORAL)
    d.text((330, 1555), "Send", font=load_font(36, bold=True), fill=(43, 18, 9))
    return screen


def mock_accept() -> Image.Image:
    screen = Image.new("RGB", (900, 1800), CREAM)
    d = ImageDraw.Draw(screen)
    d.rounded_rectangle([40, 120, 860, 220], radius=20, fill=(252, 232, 224))
    d.text((70, 150), "Needs your acceptance", font=load_font(28, bold=True), fill=CORAL)
    d.ellipse([70, 280, 150, 360], fill=CORAL_PALE)
    d.text((175, 295), "Riley", font=load_font(30, bold=True), fill=TEXT)
    d.text((175, 335), "wrote you an appreciation", font=load_font(24), fill=TEXT_SEC)
    for i, line in enumerate(
        [
            "You always notice the quiet work",
            "nobody else sees. That means",
            "everything.",
        ]
    ):
        d.text((70, 420 + i * 45), line, font=load_font(30), fill=TEXT)
    d.rounded_rectangle([40, 700, 420, 820], radius=40, fill=(240, 237, 232))
    d.text((140, 740), "Decline", font=load_font(30, bold=True), fill=TEXT)
    d.rounded_rectangle([460, 700, 860, 820], radius=40, fill=CORAL)
    d.text((580, 740), "Accept", font=load_font(30, bold=True), fill=(43, 18, 9))
    return screen


def mock_profile() -> Image.Image:
    screen = Image.new("RGB", (900, 1800), CREAM)
    d = ImageDraw.Draw(screen)
    d.ellipse([350, 100, 550, 300], fill=CORAL_PALE)
    d.text((300, 340), "Alex Rivera", font=load_font(40, bold=True), fill=TEXT)
    d.text((370, 400), "@alex", font=load_font(26), fill=TEXT_SEC)
    d.text((180, 460), "Building kinder workplaces.", font=load_font(26), fill=TEXT_SEC)
    d.rounded_rectangle([40, 560, 860, 820], radius=24, fill=(252, 232, 224))
    d.text((70, 600), "CAUSE YOU CHAMPION", font=load_font(18, bold=True), fill=TEXT_SEC)
    d.text((70, 660), "Local Food Bank", font=load_font(36, bold=True), fill=TEXT)
    d.text((70, 730), '"Because nobody should go hungry."', font=load_font(24), fill=TEXT_SEC)
    for i, (label, n) in enumerate([("Received", "12"), ("Sent", "8"), ("Inspired", "21")]):
        x = 40 + i * 280
        d.text((x + 60, 900), n, font=load_font(44, bold=True), fill=TEXT)
        d.text((x + 40, 970), label, font=load_font(24), fill=TEXT_SEC)
    return screen


def write_screenshots() -> None:
    SHOTS_67.mkdir(parents=True, exist_ok=True)
    SHOTS_65.mkdir(parents=True, exist_ok=True)
    slides = [
        (
            "01-thank-someone.png",
            "Thank the people\nwho make your week.",
            mock_feed(
                "Casey",
                [
                    "Your note after the meeting",
                    "changed how I showed up",
                    "the rest of the week.",
                ],
            ),
        ),
        (
            "02-share-appreciation.png",
            "Write it once.\nThey'll feel it forever.",
            mock_compose(),
        ),
        (
            "03-accept.png",
            "Accept kindness.\nMake it part of your story.",
            mock_accept(),
        ),
        (
            "04-world-feed.png",
            "See gratitude\nripple outward.",
            mock_feed(
                "Morgan",
                ["Thanks for covering my shift", "so I could be with family.", ""],
            ),
        ),
        (
            "05-cause.png",
            "Champion a cause\nalongside your thanks.",
            mock_profile(),
        ),
    ]
    title_font = load_font(72, bold=True)
    for filename, headline, mock in slides:
        frame = phone_frame(mock).convert("RGBA")
        mark = make_heart_layer(120).resize((64, 64), Image.Resampling.LANCZOS)
        frame.paste(mark, (80, 80), mark)
        frame = frame.convert("RGB")
        d = ImageDraw.Draw(frame)
        d.text((160, 88), "OpenThanks", font=load_font(36, bold=True), fill=TEXT)
        y = 200
        for line in headline.split("\n"):
            d.text((80, y), line, font=title_font, fill=TEXT)
            y += 90
        out = SHOTS_67 / filename
        frame.save(out, "PNG", optimize=True)
        frame.resize((1284, 2778), Image.Resampling.LANCZOS).save(
            SHOTS_65 / filename, "PNG", optimize=True
        )
        print("wrote", out.relative_to(ROOT))


def main() -> None:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    (STORE / "Icons").mkdir(parents=True, exist_ok=True)

    icon_light = make_icon((24, 15, 12))
    icon_dark = make_icon((0, 0, 0))
    icon_tinted = make_icon((0, 0, 0), white=True)

    icon_light.save(ICON_DIR / "AppIcon.png", "PNG")
    icon_dark.save(ICON_DIR / "AppIcon-Dark.png", "PNG")
    icon_tinted.save(ICON_DIR / "AppIcon-Tinted.png", "PNG")
    icon_light.save(STORE / "Icons/AppStore-Icon-1024.png", "PNG")
    icon_dark.save(STORE / "Icons/AppStore-Icon-1024-Dark.png", "PNG")
    print("icons OK (opaque RGB 1024)")

    write_screenshots()
    print("done → see AppStore/README.md")


if __name__ == "__main__":
    main()
