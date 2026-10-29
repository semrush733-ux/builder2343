#!/usr/bin/env python3
"""Draws the 2060 Tele Player launcher icons, splash logo and Android TV banner into android_overlay/."""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FONT = sys.argv[1] if len(sys.argv) > 1 else '/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf'
RES = 'android_overlay/app/src/main/res'
BG = (6, 7, 15)
STOPS = [(47, 230, 208), (123, 92, 255), (255, 79, 163)]  # mint, violet, pink


def gradient(w, h):
    """Diagonal brand gradient, w x h."""
    x = np.linspace(0, 1, w)[None, :]
    y = np.linspace(0, 1, h)[:, None]
    t = np.clip((x + y) / 2.0, 0, 1)
    out = np.zeros((h, w, 3), dtype=np.float32)
    for c in range(3):
        a, b, d = STOPS[0][c], STOPS[1][c], STOPS[2][c]
        out[..., c] = np.where(t < 0.5, a + (b - a) * (t / 0.5), b + (d - b) * ((t - 0.5) / 0.5))
    return Image.fromarray(out.astype(np.uint8), 'RGB')


def mark(size, scale=1.0, bg=None, mono=False):
    """The orbit-and-play mark in a square canvas; scale shrinks it (adaptive-icon safe zone)."""
    k = 4
    S = size * k
    mask = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(mask)
    c = S / 2
    r = S / 2 * 0.90 * scale
    ring = r * 0.15
    d.ellipse((c - r, c - r, c + r, c + r), outline=255, width=int(ring))
    # tilted orbit (thin)
    orbit = Image.new('L', (S, S), 0)
    od = ImageDraw.Draw(orbit)
    od.ellipse((c - r * 1.02, c - r * 0.40, c + r * 1.02, c + r * 0.40), outline=255, width=max(2, int(r * 0.05)))
    orbit = orbit.rotate(36, resample=Image.BICUBIC, center=(c, c))
    # play triangle
    d.polygon([(c - r * 0.22, c - r * 0.40), (c + r * 0.48, c), (c - r * 0.22, c + r * 0.40)], fill=255)
    base = Image.new('RGBA', (S, S), (0, 0, 0, 0) if bg is None else bg + (255,))
    if mono:
        solid = Image.new('RGB', (S, S), (255, 255, 255))
        base.paste(solid, (0, 0), mask)
    else:
        base.paste(gradient(S, S), (0, 0), mask)
        white = Image.new('RGB', (S, S), (255, 255, 255))
        orbit = orbit.point(lambda v: int(v * 0.40))
        base.paste(white, (0, 0), orbit)
    return base.resize((size, size), Image.LANCZOS)


def rounded_bg(size, radius_frac=0.22):
    k = 4
    S = size * k
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * radius_frac), fill=BG + (255,))
    return img.resize((size, size), Image.LANCZOS)


def legacy_icon(size, round_=False):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    if round_:
        k = 4
        m = Image.new('L', (size * k, size * k), 0)
        ImageDraw.Draw(m).ellipse((0, 0, size * k - 1, size * k - 1), fill=255)
        m = m.resize((size, size), Image.LANCZOS)
        img.paste(Image.new('RGBA', (size, size), BG + (255,)), (0, 0), m)
    else:
        img = rounded_bg(size)
    img.alpha_composite(mark(size, 0.74))
    return img


def banner(w, h):
    k = 2
    img = Image.new('RGB', (w * k, h * k), BG)
    # soft colour glows
    glow = Image.new('RGB', (w * k, h * k), BG)
    gd = ImageDraw.Draw(glow)
    gd.ellipse((-w * 0.2 * k, -h * 0.5 * k, w * 0.5 * k, h * 0.8 * k), fill=(40, 28, 110))
    gd.ellipse((w * 0.55 * k, h * 0.4 * k, w * 1.2 * k, h * 1.4 * k), fill=(10, 80, 80))
    from PIL import ImageFilter
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.35 * k))
    img = Image.blend(img, glow, 0.9)
    m = mark(int(h * 0.52 * k), 1.0)
    img_rgba = img.convert('RGBA')
    mx = int(w * 0.09 * k)
    my = int((h * k - m.size[1]) / 2)
    img_rgba.alpha_composite(m, (mx, my))
    # wordmark
    d = ImageDraw.Draw(img_rgba)
    f1 = ImageFont.truetype(FONT, int(h * 0.30 * k))
    f2 = ImageFont.truetype(FONT, int(h * 0.085 * k))
    tx = mx + m.size[0] + int(w * 0.035 * k)
    word = Image.new('L', (w * k, h * k), 0)
    ImageDraw.Draw(word).text((tx, int(h * 0.27 * k)), '2060', font=f1, fill=255)
    img_rgba.paste(gradient(w * k, h * k), (0, 0), word)
    # letter-spaced subtitle
    sx = tx + int(h * 0.01 * k)
    sy = int(h * 0.62 * k)
    for ch in 'TELE PLAYER':
        d.text((sx, sy), ch, font=f2, fill=(143, 148, 184))
        sx += d.textlength(ch, font=f2) + int(h * 0.022 * k)
    return img_rgba.convert('RGB').resize((w, h), Image.LANCZOS)


DENS = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0}
for name, f in DENS.items():
    d = f'{RES}/mipmap-{name}'
    os.makedirs(d, exist_ok=True)
    legacy_icon(int(48 * f)).save(f'{d}/ic_launcher.png')
    legacy_icon(int(48 * f), True).save(f'{d}/ic_launcher_round.png')
    fg = int(108 * f)
    mark(fg, 0.56).save(f'{d}/ic_launcher_foreground.png')
    mark(fg, 0.56, mono=True).save(f'{d}/ic_launcher_monochrome.png')
    sd = f'{RES}/drawable-{name}'
    os.makedirs(sd, exist_ok=True)
    mark(int(96 * f), 1.0).save(f'{sd}/splash_logo.png')
    banner(int(320 * f), int(180 * f)).save(f'{sd}/tv_banner.png')

with open(f'{RES}/values/ic_launcher_background.xml', 'w') as fh:
    fh.write('''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#06070F</color>
    <color name="splash_background">#06070F</color>
</resources>
''')
print('icons written')
