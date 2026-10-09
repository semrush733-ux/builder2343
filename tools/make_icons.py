#!/usr/bin/env python3
"""Draws the B1G launcher icons and the Android TV banner into android_overlay/."""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

FONT = sys.argv[1] if len(sys.argv) > 1 else '/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf'
RES = 'android_overlay/app/src/main/res'
ACCENT = (255, 196, 0)
DARK = (10, 12, 16)


def wordmark(width, height, scale):
    """Dark canvas with the yellow B1G badge in the middle (drawn 4x, then reduced)."""
    k = 4
    img = Image.new('RGB', (width * k, height * k), DARK)
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT, int(height * k * scale))
    box = d.textbbox((0, 0), 'B1G', font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    padx, pady = int(th * 0.42), int(th * 0.30)
    bw, bh = tw + 2 * padx, th + 2 * pady
    x0, y0 = (width * k - bw) // 2, (height * k - bh) // 2
    d.rounded_rectangle((x0, y0, x0 + bw, y0 + bh), radius=int(bh * 0.24), fill=ACCENT)
    d.text((x0 + padx - box[0], y0 + pady - box[1]), 'B1G', font=font, fill=(0, 0, 0))
    return img.resize((width, height), Image.LANCZOS)


for name, size in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    os.makedirs('%s/mipmap-%s' % (RES, name), exist_ok=True)
    wordmark(size, size, 0.30).save('%s/mipmap-%s/ic_launcher.png' % (RES, name))

os.makedirs(RES + '/drawable-xhdpi', exist_ok=True)
wordmark(320, 180, 0.42).save(RES + '/drawable-xhdpi/tv_banner.png')
print('icons written')
