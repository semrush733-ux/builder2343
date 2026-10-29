#!/usr/bin/env python3
"""Paints the three home-tile pictures (aurora lake, film reel, poster wall) into assets/tiles/."""
import math
import random

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = 'assets/tiles'
rnd = random.Random(2060)
nrnd = np.random.RandomState(2060)


def lerp(a, b, t):
    return a + (b - a) * t


def vgrad(w, h, stops):
    """Vertical gradient; stops = [(pos 0..1, (r,g,b))]."""
    y = np.linspace(0, 1, h)[:, None]
    out = np.zeros((h, w, 3), dtype=np.float32)
    for c in range(3):
        xs = [p for p, _ in stops]
        vs = [col[c] for _, col in stops]
        out[..., c] = np.interp(y, xs, vs)
    return Image.fromarray(out.astype(np.uint8), 'RGB')


def ridge(w, base, rough, seed, detail=7, amp=1.0):
    """Mountain ridge line (array of y per x) by midpoint displacement."""
    r = random.Random(seed)
    n = 2 ** detail
    pts = [0.0] * (n + 1)
    pts[0] = r.uniform(-1, 1)
    pts[n] = r.uniform(-1, 1)
    step = n
    scale = 1.0
    while step > 1:
        half = step // 2
        for i in range(half, n, step):
            pts[i] = (pts[i - half] + pts[i + half]) / 2 + r.uniform(-scale, scale)
        scale *= rough
        step = half
    xs = np.linspace(0, n, w)
    arr = np.interp(xs, np.arange(n + 1), pts)
    return base + arr * amp


def glow_layer(size, draw_fn, blur):
    im = Image.new('RGB', size, (0, 0, 0))
    d = ImageDraw.Draw(im)
    draw_fn(d)
    return im.filter(ImageFilter.GaussianBlur(blur))


def screen(a, b):
    return ImageChops.screen(a, b)


# ------------------------------------------------------------------ live: aurora lake
def live(w=1280, h=960):
    horizon = int(h * 0.60)
    sky = vgrad(w, horizon, [(0, (6, 8, 38)), (0.45, (28, 22, 96)), (0.8, (120, 62, 150)), (1.0, (230, 120, 130))])
    img = Image.new('RGB', (w, h), (5, 6, 24))
    img.paste(sky, (0, 0))
    # stars
    d = ImageDraw.Draw(img)
    for _ in range(420):
        x, y = rnd.randint(0, w), rnd.randint(0, int(horizon * 0.85))
        b = rnd.randint(120, 255)
        r = rnd.choice([0, 0, 0, 1])
        d.ellipse((x - r, y - r, x + r, y + r), fill=(b, b, min(255, b + 20)))
    # aurora ribbon
    def ribbon(dd):
        for k, (col, wd) in enumerate([((60, 255, 200), 54), ((150, 90, 255), 80), ((255, 90, 190), 60)]):
            pts = []
            for i in range(0, 41):
                t = i / 40
                x = lerp(-0.1, 1.1, t) * w
                y = horizon * (0.62 - 0.40 * t) + math.sin(t * 6 + k) * 34 + k * 40
                pts.append((x, y))
            dd.line(pts, fill=col, width=wd, joint='curve')
    aur = glow_layer((w, h), ribbon, 38)
    aur = Image.eval(aur, lambda v: int(v * 0.55))
    img = screen(img, aur)
    # mountains: three layers, each filled with a gradient that is lighter at the peaks
    layers = [
        (0.30, 0.17, 11, (84, 70, 150), (30, 26, 84)),
        (0.40, 0.15, 23, (56, 48, 118), (20, 18, 60)),
        (0.50, 0.11, 37, (30, 28, 78), (12, 12, 40)),
    ]
    scene = img.copy()
    sd = ImageDraw.Draw(scene)
    for base_f, amp_f, seed, light, dark in layers:
        line = ridge(w, h * base_f, 0.58, seed, amp=h * amp_f)
        poly = [(0, horizon + 4)] + [(x, min(horizon, line[x])) for x in range(w)] + [(w, horizon + 4)]
        m = Image.new('L', (w, h), 0)
        ImageDraw.Draw(m).polygon(poly, fill=255)
        top_y = int(min(line))
        grad = vgrad(w, h, [(0, light), (max(0.01, top_y / h), light), (horizon / h, dark), (1, dark)])
        scene.paste(grad, (0, 0), m)
    sd = ImageDraw.Draw(scene)
    # near forest silhouette
    line = ridge(w, h * 0.625, 0.5, 91, amp=h * 0.018)
    forest = [(0, horizon + 6)] + [(x, min(horizon + 2, line[x])) for x in range(w)] + [(w, horizon + 6)]
    sd.polygon(forest, fill=(6, 8, 22))
    for _ in range(170):
        x = rnd.randint(0, w)
        ty = min(horizon + 2, line[min(w - 1, x)])
        th = rnd.randint(14, 38)
        sd.polygon([(x - th * 0.22, ty + 6), (x, ty - th), (x + th * 0.22, ty + 6)], fill=(6, 8, 22))
    # village lights
    for _ in range(36):
        x = rnd.randint(int(w * 0.3), int(w * 0.75))
        y = horizon - rnd.randint(0, 6)
        sd.ellipse((x - 1, y - 1, x + 1, y + 1), fill=(255, 200, 120))
    # lake: mirrored scene, blurred, darkened, ripples
    top = scene.crop((0, 0, w, horizon))
    mirror = top.transpose(Image.FLIP_TOP_BOTTOM).resize((w, h - horizon))
    mirror = mirror.filter(ImageFilter.GaussianBlur(5))
    arr = np.asarray(mirror).astype(np.float32)
    arr *= np.linspace(0.78, 0.35, h - horizon)[:, None, None]
    # horizontal ripples
    for y in range(0, h - horizon, 3):
        shift = int(math.sin(y * 0.55) * 4)
        arr[y] = np.roll(arr[y], shift, axis=0)
    lake = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB')
    scene.paste(lake, (0, horizon))
    ld = ImageDraw.Draw(scene)
    for _ in range(26):
        x = rnd.randint(int(w * 0.3), int(w * 0.75))
        y = horizon + rnd.randint(4, 40)
        ld.line((x - rnd.randint(3, 14), y, x + rnd.randint(3, 14), y), fill=(255, 190, 120))
    scene = scene.filter(ImageFilter.GaussianBlur(0.8))
    return scene


# ------------------------------------------------------------------ movies: reel + film strip
def movies(w=960, h=720):
    bg = vgrad(w, h, [(0, (62, 20, 90)), (0.55, (40, 14, 64)), (1, (22, 8, 40))])
    img = bg.copy()
    # bokeh
    bok = Image.new('RGB', (w, h), (0, 0, 0))
    bd = ImageDraw.Draw(bok)
    for _ in range(26):
        x, y, r = rnd.randint(0, w), rnd.randint(0, h), rnd.randint(14, 54)
        c = rnd.choice([(255, 150, 60), (255, 90, 170), (150, 90, 255)])
        bd.ellipse((x - r, y - r, x + r, y + r), fill=tuple(int(v * 0.35) for v in c))
    img = screen(img, bok.filter(ImageFilter.GaussianBlur(10)))
    # film strip across the lower right (drawn big, then rotated)
    strip = Image.new('RGBA', (w * 2, 230), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strip)
    sd.rectangle((0, 0, w * 2, 230), fill=(14, 10, 20, 255))
    for i in range(0, w * 2, 46):
        sd.rounded_rectangle((i + 8, 12, i + 32, 34), radius=4, fill=(60, 44, 72, 255))
        sd.rounded_rectangle((i + 8, 196, i + 32, 218), radius=4, fill=(60, 44, 72, 255))
    for i in range(0, w * 2, 168):
        c = rnd.choice([((255, 160, 80), (140, 50, 160)), ((90, 220, 220), (60, 70, 190)), ((255, 100, 160), (90, 40, 140))])
        fr = Image.new('RGB', (150, 150))
        fr.paste(vgrad(150, 150, [(0, c[0]), (1, c[1])]))
        fd = ImageDraw.Draw(fr)
        fd.ellipse((50, 30, 100, 80), fill=(20, 12, 30))
        fd.rectangle((32, 90, 118, 150), fill=(20, 12, 30))
        strip.paste(fr, (i + 8, 40))
    strip = strip.rotate(18, expand=True, resample=Image.BICUBIC)
    img.paste(strip, (int(w * 0.18), int(h * 0.30) - strip.size[1] // 2 + 140), strip)
    # reel
    reel = Image.new('RGBA', (560, 560), (0, 0, 0, 0))
    rd = ImageDraw.Draw(reel)
    rd.ellipse((10, 10, 550, 550), fill=(200, 150, 70, 255))
    rd.ellipse((30, 30, 530, 530), fill=(120, 78, 30, 255))
    rd.ellipse((46, 46, 514, 514), fill=(214, 166, 84, 255))
    for k in range(6):
        a = k * math.pi / 3
        cx, cy = 280 + math.cos(a) * 170, 280 + math.sin(a) * 170
        rd.ellipse((cx - 62, cy - 62, cx + 62, cy + 62), fill=(34, 18, 40, 255))
    rd.ellipse((220, 220, 340, 340), fill=(240, 200, 120, 255))
    rd.ellipse((258, 258, 302, 302), fill=(34, 18, 40, 255))
    reel = reel.rotate(-12, resample=Image.BICUBIC)
    sh = Image.new('RGBA', reel.size, (0, 0, 0, 0))
    img.paste(reel.resize((470, 470)), (int(w * 0.50), int(h * -0.10)), reel.resize((470, 470)))
    # warm rim light from the right
    glow = Image.new('RGB', (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((w * 0.62, h * 0.05, w * 1.3, h * 0.9), fill=(120, 60, 20))
    img = screen(img, glow.filter(ImageFilter.GaussianBlur(90)))
    return img.filter(ImageFilter.GaussianBlur(0.6))


# ------------------------------------------------------------------ series: poster wall in perspective
def series(w=960, h=720):
    base = vgrad(w, h, [(0, (6, 40, 52)), (1, (8, 14, 36))])
    wall = Image.new('RGB', (1500, 1000), (8, 16, 30))
    wd = ImageDraw.Draw(wall)
    pw, ph, gap = 210, 300, 14
    tints = [(30, 120, 130), (40, 70, 140), (20, 100, 100), (70, 50, 120), (30, 90, 120)]
    for row in range(4):
        for col in range(8):
            x = 20 + col * (pw + gap)
            y = 14 + row * (ph + gap)
            t1 = rnd.choice(tints)
            t2 = tuple(int(c * 0.25) for c in t1)
            p = vgrad(pw, ph, [(0, t1), (0.55, t2), (1, (6, 10, 20))])
            pd = ImageDraw.Draw(p)
            # silhouette: head + shoulders
            cx = pw // 2 + rnd.randint(-20, 20)
            pd.ellipse((cx - 34, 64, cx + 34, 142), fill=(10, 14, 24))
            pd.polygon([(cx - 90, ph), (cx - 60, 160), (cx + 60, 160), (cx + 90, ph)], fill=(10, 14, 24))
            # title bar
            pd.rectangle((24, ph - 46, pw - 24, ph - 38), fill=(190, 210, 220))
            pd.rectangle((24, ph - 30, pw * 0.6, ph - 24), fill=(120, 140, 150))
            wall.paste(p, (x, y))
    # rim light on the edges of posters
    wall = wall.filter(ImageFilter.GaussianBlur(0.6))
    # perspective tilt
    src = (0, 0, 1500, 0, 1500, 1000, 0, 1000)
    dst = [(w * 0.18, h * 0.05), (w * 1.02, -h * 0.12), (w * 1.02, h * 1.05), (w * 0.18, h * 0.92)]
    coeffs = []
    for (x, y), (X, Y) in zip(dst, [(0, 0), (1500, 0), (1500, 1000), (0, 1000)]):
        coeffs.append(((x, y), (X, Y)))
    A = []
    B = []
    for (x, y), (X, Y) in coeffs:
        A.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        A.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
        B.extend([X, Y])
    res = np.linalg.solve(np.array(A, dtype=np.float64), np.array(B, dtype=np.float64))
    warped = wall.transform((w, h), Image.PERSPECTIVE, tuple(res), Image.BICUBIC, fillcolor=(0, 0, 0))
    mask = Image.new('L', (w, h), 0)
    ImageDraw.Draw(mask).polygon(dst, fill=255)
    base.paste(warped, (0, 0), mask)
    # fade the left side so the title stays readable, add teal glow
    fade = Image.new('L', (w, h))
    fa = np.tile(np.linspace(235, 0, w)[None, :], (h, 1)).astype(np.uint8)
    fade = Image.fromarray(fa, 'L')
    base = Image.composite(Image.new('RGB', (w, h), (6, 30, 40)), base, fade)
    glow = Image.new('RGB', (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((w * 0.4, h * 0.2, w * 1.1, h * 1.0), fill=(10, 90, 100))
    base = screen(base, glow.filter(ImageFilter.GaussianBlur(100)))
    return base


if __name__ == '__main__':
    import os
    os.makedirs(OUT, exist_ok=True)
    live().save(f'{OUT}/live.webp', quality=82)
    movies().save(f'{OUT}/movies.webp', quality=82)
    series().save(f'{OUT}/series.webp', quality=82)
    print('tiles written')
