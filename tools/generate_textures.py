#!/usr/bin/env python3
"""Generates Velicia's procedural PBR textures (tileable albedo + normal maps).

All textures are original, made from filtered noise, so they carry no third-party
licence. They are a big step up from flat colours, but still stand-ins: swap in
photo-scanned CC0 sets later by overwriting the files (same names).

Usage:  python3 tools/generate_textures.py   (needs numpy + Pillow)
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "textures")
SIZE = 512
rng = np.random.default_rng(11)


# ----------------------------------------------------------------- noise

def spectral_noise(size, beta=2.0, lo=1.0, hi=None, seed=None):
    """Tileable noise with a 1/f^beta spectrum (FFT-filtered white noise)."""
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((size, size))
    f = np.fft.fftfreq(size) * size
    fx, fy = np.meshgrid(f, f)
    freq = np.sqrt(fx * fx + fy * fy)
    freq[0, 0] = 1.0
    amp = 1.0 / freq ** (beta / 2.0)
    amp[freq < lo] = 0.0
    if hi is not None:
        amp[freq > hi] = 0.0
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    out -= out.min()
    return out / (out.max() or 1.0)


def ridged(size, beta=2.0, lo=2.0, seed=None):
    n = spectral_noise(size, beta, lo, seed=seed)
    return 1.0 - np.abs(n * 2.0 - 1.0)


def stretch_noise(size, sx, sy, beta=1.6, seed=None):
    """Anisotropic noise (streaks), still tileable."""
    r = np.random.default_rng(seed) if seed is not None else rng
    white = r.standard_normal((size, size))
    f = np.fft.fftfreq(size) * size
    fx, fy = np.meshgrid(f, f)
    freq = np.sqrt((fx * sx) ** 2 + (fy * sy) ** 2)
    freq[0, 0] = 1.0
    out = np.real(np.fft.ifft2(np.fft.fft2(white) / freq ** (beta / 2.0)))
    out -= out.min()
    return out / (out.max() or 1.0)


def normal_from_height(h, strength=4.0):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    n = np.stack([-dx, -dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def colorize(t, stops):
    """Map t in 0..1 through colour stops [(pos, (r,g,b)), ...]."""
    pos = np.array([s[0] for s in stops])
    cols = np.array([s[1] for s in stops], dtype=float)
    out = np.zeros(t.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(t, pos, cols[:, c])
    return out


def save(name, albedo, height=None, strength=4.0, alpha=None):
    os.makedirs(ROOT, exist_ok=True)
    rgb = np.clip(albedo * 255, 0, 255).astype(np.uint8)
    if alpha is not None:
        a = np.clip(alpha * 255, 0, 255).astype(np.uint8)
        Image.fromarray(np.dstack([rgb, a]), "RGBA").save(os.path.join(ROOT, name + "_albedo.png"))
    else:
        Image.fromarray(rgb, "RGB").save(os.path.join(ROOT, name + "_albedo.png"))
    if height is not None:
        Image.fromarray(normal_from_height(height, strength), "RGB").save(os.path.join(ROOT, name + "_normal.png"))
    print("wrote", name)


def specks(size, count, radius, seed):
    """Tileable round pebbles/blobs as a height field."""
    r = np.random.default_rng(seed)
    h = np.zeros((size, size))
    yy, xx = np.mgrid[0:size, 0:size]
    for _ in range(count):
        cx, cy = r.uniform(0, size, 2)
        rad = r.uniform(radius * 0.4, radius)
        dx = np.minimum(np.abs(xx - cx), size - np.abs(xx - cx))
        dy = np.minimum(np.abs(yy - cy), size - np.abs(yy - cy))
        d = np.sqrt(dx * dx + dy * dy) / rad
        h = np.maximum(h, np.clip(1.0 - d * d, 0, 1) * r.uniform(0.5, 1.0))
    return h


# --------------------------------------------------------------- materials

def grass():
    base = spectral_noise(SIZE, 1.8, 1.0, seed=1)
    fine = spectral_noise(SIZE, 0.6, 30.0, seed=2)
    blades = stretch_noise(SIZE, 1.0, 6.0, 1.2, seed=3)
    t = np.clip(base * 0.55 + fine * 0.3 + blades * 0.25, 0, 1)
    col = colorize(t, [(0.0, (0.12, 0.2, 0.06)), (0.35, (0.2, 0.33, 0.1)), (0.6, (0.3, 0.44, 0.14)),
                       (0.85, (0.42, 0.5, 0.2)), (1.0, (0.55, 0.55, 0.3))])
    dry = spectral_noise(SIZE, 2.2, 1.0, seed=4)
    col = col * (1 - dry[..., None] * 0.25) + np.array([0.5, 0.45, 0.25]) * dry[..., None] * 0.25
    save("grass", col, fine * 0.6 + blades * 0.4, 3.0)


def dirt():
    base = spectral_noise(SIZE, 2.0, 1.0, seed=5)
    fine = spectral_noise(SIZE, 0.8, 20.0, seed=6)
    peb = specks(SIZE, 260, 9, seed=7)
    h = base * 0.4 + fine * 0.3 + peb * 0.6
    t = np.clip(base * 0.6 + fine * 0.4, 0, 1)
    col = colorize(t, [(0.0, (0.2, 0.14, 0.09)), (0.5, (0.36, 0.27, 0.18)), (1.0, (0.5, 0.4, 0.28))])
    col = col * (1 - peb[..., None] * 0.5) + np.array([0.52, 0.48, 0.44]) * peb[..., None] * 0.5
    save("dirt", col, h, 5.0)


def rock():
    strata = stretch_noise(SIZE, 0.25, 2.5, 2.0, seed=8)
    crack = ridged(SIZE, 1.4, 6.0, seed=9) ** 6
    base = spectral_noise(SIZE, 2.0, 1.0, seed=10)
    fine = spectral_noise(SIZE, 0.7, 40.0, seed=11)
    h = base * 0.5 + strata * 0.3 + fine * 0.2 - crack * 0.5
    t = np.clip(base * 0.5 + strata * 0.3 + fine * 0.3, 0, 1)
    col = colorize(t, [(0.0, (0.22, 0.21, 0.2)), (0.4, (0.38, 0.36, 0.33)), (0.75, (0.52, 0.5, 0.46)), (1.0, (0.64, 0.62, 0.58))])
    lichen = np.clip(spectral_noise(SIZE, 2.4, 2.0, seed=12) - 0.62, 0, 1) * 2.5
    col = col * (1 - lichen[..., None] * 0.6) + np.array([0.42, 0.46, 0.25]) * lichen[..., None] * 0.6
    col *= (1 - crack[..., None] * 0.6)
    save("rock", col, h, 6.0)


def sand():
    base = spectral_noise(SIZE, 1.8, 1.0, seed=13)
    ripples = stretch_noise(SIZE, 4.0, 0.6, 1.4, seed=14)
    fine = rng.random((SIZE, SIZE)) * 0.3
    h = ripples * 0.6 + base * 0.3 + fine * 0.1
    col = colorize(np.clip(base * 0.6 + ripples * 0.3 + fine, 0, 1), [(0.0, (0.5, 0.45, 0.33)), (1.0, (0.78, 0.71, 0.54))])
    save("sand", col, h, 3.0)


def snow():
    base = spectral_noise(SIZE, 2.0, 1.0, seed=15)
    fine = spectral_noise(SIZE, 0.9, 20.0, seed=16)
    col = colorize(np.clip(base * 0.7 + fine * 0.3, 0, 1), [(0.0, (0.72, 0.76, 0.84)), (1.0, (0.96, 0.97, 1.0))])
    save("snow", col, base * 0.7 + fine * 0.3, 2.5)


def bark():
    streak = stretch_noise(SIZE, 0.35, 8.0, 1.8, seed=17)
    crack = (1.0 - np.abs(stretch_noise(SIZE, 0.5, 6.0, 1.4, seed=18) * 2 - 1)) ** 8
    fine = spectral_noise(SIZE, 0.8, 30.0, seed=19)
    h = streak * 0.7 + fine * 0.3 - crack * 0.6
    col = colorize(np.clip(streak * 0.7 + fine * 0.3, 0, 1), [(0.0, (0.13, 0.09, 0.06)), (0.5, (0.27, 0.19, 0.12)), (1.0, (0.42, 0.33, 0.24))])
    col *= (1 - crack[..., None] * 0.7)
    save("bark", col, h, 7.0)


def leaves():
    """Alpha-cutout cluster of leaves for tree cards (RGBA)."""
    s = 256
    r = np.random.default_rng(20)
    alpha = np.zeros((s, s))
    col = np.zeros((s, s, 3))
    yy, xx = np.mgrid[0:s, 0:s] / s
    for _ in range(70):
        cx, cy = r.uniform(0.12, 0.88, 2)
        ang = r.uniform(0, np.pi)
        length, width = r.uniform(0.07, 0.13), r.uniform(0.03, 0.05)
        dx, dy = xx - cx, yy - cy
        u = dx * np.cos(ang) + dy * np.sin(ang)
        v = -dx * np.sin(ang) + dy * np.cos(ang)
        shape = (u / length) ** 2 + (v / (width * (1 - np.abs(u / length) ** 2 + 0.1))) ** 2
        leaf = shape < 1.0
        shade = r.uniform(0.6, 1.0)
        tone = np.array([0.18, 0.34, 0.1]) * shade + np.array([0.12, 0.1, 0.0]) * r.uniform(0, 1)
        vein = np.exp(-(v / 0.004) ** 2) * 0.25
        col[leaf] = tone * (1.0 - vein[leaf, None]) + (0.5 + 0.5 * u[leaf, None] / length) * 0.04
        alpha[leaf] = 1.0
    save("leaves", col, None, alpha=alpha)


def needles():
    """Fir branch card (RGBA): a twig with a dense, tapering spray of needles."""
    s = 256
    alpha = np.zeros((s, s))
    col = np.zeros((s, s, 3))
    r = np.random.default_rng(21)
    yy, xx = np.mgrid[0:s, 0:s] / s
    # Soft spray silhouette: widest near the base, pointed at the tip (v=0).
    width = 0.46 * np.clip(yy, 0.0, 1.0) ** 0.6
    spray = np.abs(xx - 0.5) < width * (0.75 + 0.25 * np.sin(yy * 40.0) ** 2)
    base_noise = spectral_noise(s, 0.8, 20.0, seed=50)
    for i in range(900):
        y0 = r.uniform(0.04, 0.98)
        side = 1 if i % 2 else -1
        length = 0.46 * y0 ** 0.6 * r.uniform(0.6, 1.0)
        ang = r.uniform(0.45, 0.9)
        t = np.linspace(0, 1, 40)
        px = 0.5 + side * t * length * np.cos(ang)
        py = y0 - t * length * np.sin(ang) * 0.5
        shade = r.uniform(0.75, 1.25)
        for x, y in zip(px, py):
            ix, iy = int(x * s), int(y * s)
            if 0 <= ix < s and 0 <= iy < s:
                alpha[iy, ix] = 1
                col[iy, ix] = np.array([0.09, 0.22, 0.11]) * shade
    for _ in range(2):
        alpha = np.maximum.reduce([alpha, np.roll(alpha, 1, 1), np.roll(alpha, 1, 0), np.roll(alpha, -1, 1)])
        col = np.maximum.reduce([col, np.roll(col, 1, 1), np.roll(col, 1, 0), np.roll(col, -1, 1)])
    # Fill the spray interior so the card keeps coverage at a distance.
    fill = spray & (alpha < 0.5)
    alpha[fill] = 0.85
    col[fill] = (np.array([0.06, 0.16, 0.08])[None, :] * (0.8 + 0.4 * base_noise[fill, None]))
    twig = (np.abs(xx - 0.5) < 0.012) & (yy > 0.03)
    col[twig] = (0.28, 0.19, 0.11)
    alpha[twig] = 1
    save("needles", col, None, alpha=alpha)


def stone_wall():
    s = SIZE
    yy, xx = np.mgrid[0:s, 0:s]
    rows = 8
    bh = s // rows
    row = yy // bh
    offset = (row % 2) * (s // 8)
    bw = s // 4
    col_idx = ((xx + offset) % s) // bw
    lx = ((xx + offset) % s) % bw
    ly = yy % bh
    mortar = (lx < 5) | (ly < 5)
    r = np.random.default_rng(22)
    tint = r.uniform(0.75, 1.1, (rows, 5))
    block_tint = tint[row, col_idx % 5]
    base = spectral_noise(s, 1.8, 2.0, seed=23)
    fine = spectral_noise(s, 0.8, 30.0, seed=24)
    edge = np.minimum(np.minimum(lx, bw - lx), np.minimum(ly, bh - ly)) / 12.0
    bevel = np.clip(edge, 0, 1)
    h = np.where(mortar, 0.0, bevel * 0.6 + base * 0.25 + fine * 0.15)
    stone = colorize(np.clip(base * 0.6 + fine * 0.4, 0, 1), [(0.0, (0.33, 0.31, 0.28)), (1.0, (0.6, 0.57, 0.52))]) * block_tint[..., None]
    col = np.where(mortar[..., None], np.array([0.25, 0.23, 0.2]), stone)
    save("stone_wall", np.clip(col, 0, 1), h, 6.0)


def planks():
    s = SIZE
    yy, xx = np.mgrid[0:s, 0:s]
    pw = s // 6
    idx = xx // pw
    lx = xx % pw
    grain = stretch_noise(s, 10.0, 0.3, 1.6, seed=25)
    knots = specks(s, 10, 14, seed=26)
    r = np.random.default_rng(27)
    tint = r.uniform(0.8, 1.15, 8)[idx]
    gap = lx < 3
    h = np.where(gap, 0.0, 0.6 + grain * 0.3 - knots * 0.3)
    col = colorize(np.clip(grain * 0.8 + knots * 0.3, 0, 1), [(0.0, (0.25, 0.16, 0.09)), (1.0, (0.55, 0.4, 0.25))]) * tint[..., None]
    col = np.where(gap[..., None], np.array([0.08, 0.06, 0.04]), col)
    save("planks", np.clip(col, 0, 1), h, 5.0)


def fabric():
    s = SIZE
    yy, xx = np.mgrid[0:s, 0:s]
    weave = (np.sin(xx * np.pi / 3.0) * np.sin(yy * np.pi / 3.0)) * 0.5 + 0.5
    base = spectral_noise(s, 1.5, 4.0, seed=28)
    h = weave * 0.6 + base * 0.4
    col = np.ones((s, s, 3)) * (0.75 + 0.2 * weave[..., None] + 0.1 * base[..., None])
    save("fabric", np.clip(col, 0, 1), h, 2.0)


def leather():
    base = spectral_noise(SIZE, 1.6, 3.0, seed=29)
    cells = ridged(SIZE, 1.2, 25.0, seed=30) ** 3
    h = base * 0.4 + cells * 0.6
    col = np.ones((SIZE, SIZE, 3)) * (0.7 + 0.25 * base[..., None] - 0.2 * cells[..., None])
    save("leather", np.clip(col, 0, 1), h, 3.0)


def metal():
    brushed = stretch_noise(SIZE, 0.2, 8.0, 1.2, seed=31)
    scratches = (1.0 - np.abs(stretch_noise(SIZE, 0.15, 6.0, 0.9, seed=32) * 2 - 1)) ** 20
    dents = spectral_noise(SIZE, 2.2, 2.0, seed=33)
    h = dents * 0.5 + brushed * 0.3 - scratches * 0.3
    col = np.ones((SIZE, SIZE, 3)) * (0.75 + 0.15 * brushed[..., None] + 0.2 * scratches[..., None] - 0.15 * dents[..., None])
    save("metal", np.clip(col, 0, 1), h, 2.0)


def skin():
    pores = spectral_noise(SIZE, 0.6, 60.0, seed=34)
    blotch = spectral_noise(SIZE, 2.0, 2.0, seed=35)
    h = pores * 0.7 + blotch * 0.3
    col = np.ones((SIZE, SIZE, 3)) * (0.92 + 0.06 * blotch[..., None] - 0.04 * pores[..., None])
    col[..., 0] += 0.04 * blotch
    save("skin", np.clip(col, 0, 1), h, 1.2)


def fur():
    strands = stretch_noise(SIZE, 6.0, 0.25, 1.0, seed=36)
    base = spectral_noise(SIZE, 1.8, 2.0, seed=37)
    h = strands * 0.8 + base * 0.2
    col = np.ones((SIZE, SIZE, 3)) * (0.6 + 0.45 * strands[..., None])
    save("fur", np.clip(col, 0, 1), h, 4.0)


def scales():
    # Overlapping rounded scales in offset rows (Vapouriun skin); tiles exactly.
    n = 16
    cell = SIZE // n
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    row = np.floor(y / cell)
    xo = x + (row % 2) * cell * 0.5
    u = (xo % cell) / cell - 0.5
    v = (y % cell) / cell
    d = np.sqrt(u * u * 1.4 + (v * 0.9) ** 2)
    h = np.clip(1.0 - d, 0.0, 1.0) ** 0.6
    edge = np.clip((d - 0.62) * 6.0, 0.0, 1.0)
    fine = spectral_noise(SIZE, 1.0, 30.0, seed=42)
    h = h * (1.0 - edge) + fine * 0.15
    col = np.ones((SIZE, SIZE, 3)) * (0.62 + 0.38 * h[..., None] - 0.25 * edge[..., None])
    save("scales", np.clip(col, 0, 1), h, 5.0)


def water_normal():
    h = spectral_noise(SIZE, 2.2, 2.0, seed=38) * 0.7 + spectral_noise(SIZE, 1.4, 10.0, seed=39) * 0.3
    os.makedirs(ROOT, exist_ok=True)
    Image.fromarray(normal_from_height(h, 3.0), "RGB").save(os.path.join(ROOT, "water_normal.png"))
    print("wrote water_normal")


def cloud_noise():
    n = spectral_noise(SIZE, 2.2, 1.0, seed=40)
    m = spectral_noise(SIZE, 1.6, 4.0, seed=41)
    rgb = np.dstack([n, m, (n + m) * 0.5])
    Image.fromarray((rgb * 255).astype(np.uint8), "RGB").save(os.path.join(ROOT, "noise.png"))
    print("wrote noise")


if __name__ == "__main__":
    for fn in [grass, dirt, rock, sand, snow, bark, leaves, needles, stone_wall, planks, fabric, leather, metal, skin, fur, scales, water_normal, cloud_noise]:
        fn()
