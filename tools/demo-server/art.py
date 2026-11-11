"""Artwork for the demo catalogue, drawn from scratch so nothing in the screenshots is anyone's
copyright: skies, suns and moons, layered hills, stars, and titles set in Inter (SIL OFL)."""

import io
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTS = Path(__file__).resolve().parents[2] / "TV" / "Fonts"


def font(size, weight="ExtraBold"):
    return ImageFont.truetype(str(FONTS / f"Inter-{weight}.ttf"), size)


def _lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _sky(draw, w, h, top, bottom):
    for y in range(h):
        draw.line([(0, y), (w, y)], fill=_lerp(top, bottom, y / max(h - 1, 1)))


def scene(palette, w, h, seed, night=False, orb=True):
    """A landscape: sky, an optional sun or moon with its glow, stars at night, then hills."""
    rnd = random.Random(seed)
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    sky_top, sky_bottom, orb_colour, hills = palette
    _sky(draw, w, h, sky_top, sky_bottom)
    if night:
        for _ in range(int(w * h / 4000)):
            x, y = rnd.random() * w, rnd.random() * h * 0.6
            r = rnd.choice([1, 1, 1, 2])
            draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255))
    if orb:
        cx, cy = w * (0.55 + rnd.random() * 0.3), h * (0.28 + rnd.random() * 0.12)
        radius = min(w, h) * 0.09
        glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow)
        for i in range(12, 0, -1):
            r = radius * (1 + i * 0.35)
            glow_draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=orb_colour + (int(10 + 6 * (12 - i)),))
        glow = glow.filter(ImageFilter.GaussianBlur(radius * 0.4))
        img.paste(glow, (0, 0), glow)
        draw = ImageDraw.Draw(img)
        draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=orb_colour)
    for layer, colour in enumerate(hills):
        base = h * (0.55 + layer * 0.12)
        points = [(0, h)]
        x, y = 0, base
        step = w / 40
        while x <= w + step:
            y = base + math.sin(x / w * math.pi * (2 + layer) + seed) * h * 0.05 + rnd.uniform(-1, 1) * h * 0.02
            points.append((x, y))
            x += step
        points.append((w, h))
        draw.polygon(points, fill=colour)
    return img


def _shade_bottom(img, strength=200):
    w, h = img.size
    shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shade)
    for y in range(h // 2, h):
        a = int(strength * (y - h / 2) / (h / 2))
        draw.line([(0, y), (w, y)], fill=(0, 0, 0, a))
    out = img.convert("RGBA")
    out.alpha_composite(shade)
    return out.convert("RGB")


def _wrap(text, fnt, width, draw):
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=fnt) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def poster(title, palette, seed, night):
    img = _shade_bottom(scene(palette, 600, 900, seed, night))
    draw = ImageDraw.Draw(img)
    fnt = font(78)
    lines = _wrap(title.upper(), fnt, 520, draw)
    y = 900 - 70 - len(lines) * 84
    for line in lines:
        tw = draw.textlength(line, font=fnt)
        draw.text(((600 - tw) / 2, y), line, font=fnt, fill=(255, 255, 255))
        y += 84
    return img


def backdrop(palette, seed, night, w=1920, h=1080):
    return scene(palette, w, h, seed, night)


def logo(title):
    """The title on its own, white on clear, as a title's logo artwork is."""
    fnt = font(150)
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    lines = _wrap(title.upper(), fnt, 1100, probe)
    width = int(max(probe.textlength(l, font=fnt) for l in lines)) + 20
    img = Image.new("RGBA", (width, len(lines) * 160 + 20), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        draw.text((10, 10 + i * 160), line, font=fnt, fill=(255, 255, 255, 255))
    return img


def avatar(name, colour):
    img = Image.new("RGB", (256, 256), colour)
    draw = ImageDraw.Draw(img)
    fnt = font(120, "Bold")
    letter = name[:1].upper()
    tw = draw.textlength(letter, font=fnt)
    draw.text(((256 - tw) / 2, 52), letter, font=fnt, fill=(30, 30, 40))
    return img


def png(img):
    out = io.BytesIO()
    img.save(out, "PNG")
    return out.getvalue()


def jpeg(img):
    out = io.BytesIO()
    img.convert("RGB").save(out, "JPEG", quality=88)
    return out.getvalue()
