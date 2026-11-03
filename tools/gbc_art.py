#!/usr/bin/env python3
"""Game Boy Color-style art for Velicia, drawn from code (all original).

Rules followed, like real GBC games: 16x16 metatiles, every tile and sprite
uses at most 4 colours from a small palette, 16x16 overworld sprites with
3-frame walks, 8 px pixel font, and 4-colour battle sprites.

    python3 tools/gbc_art.py [--preview]

Writes res://art/ (tiles.png + tiles.json, chars/*.png, battle/*.png,
font.png + font.json, ui/*.png). Preview sheets go to tools/art_preview/.
"""
import json
import math
import os
import shutil
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_art as M  # noqa: E402  (Canvas, character and creature drawing)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
ART = os.path.join(ROOT, "art")
T = 16
hexc = M.hexc

# ------------------------------------------------------------------ palettes (light -> dark)
PAL = {
    "grass": ["f0f8d0", "98d068", "58a040", "204020"],
    "tree": ["e8f8b0", "70b848", "307830", "102818"],
    "path": ["f8f0d8", "e8d098", "c09860", "605028"],
    "sand": ["f8f8e0", "f0e0a8", "d0b878", "706040"],
    "water": ["f0f8ff", "90d0f8", "4890e0", "183870"],
    "stone": ["f8f8f8", "c8c8d0", "888898", "303040"],
    "rock": ["f0e8d8", "c8b098", "907058", "382818"],
    "wood": ["f8e8c8", "e0b070", "a87040", "482810"],
    "roof_red": ["f8e0c8", "f08858", "c04830", "401810"],
    "roof_blue": ["e8f0f8", "88b8f0", "3868c8", "102050"],
    "roof_green": ["f0f8e0", "98d070", "488838", "183018"],
    "wall": ["f8f8f0", "e8dcc0", "b09878", "403020"],
    "floor": ["f8e8c8", "e8c088", "b88850", "503018"],
    "inwall": ["f8f8f0", "d8e0f0", "98a8c8", "283048"],
    "flower": ["f8f8f8", "f8c0d0", "e05878", "204020"],
    "glow": ["ffffff", "a8f0ff", "48b8e8", "183870"],
    "fire": ["fff8c0", "f8c040", "e86020", "401808"],
    "tent": ["f8e8d0", "c8a070", "886040", "382010"],
    "tent_red": ["f8d8c8", "d07050", "903828", "381010"],
    "ui": ["f8f8f8", "c8d0e0", "6878a0", "181818"],
}


def pal(name):
    return [hexc(c) for c in PAL[name]]


def quantize(canvas, n=4, keep_dark=True):
    """Reduce a canvas to at most n opaque colours (GBC sprite limit)."""
    px = canvas.px
    mask = px[:, :, 3] > 0
    if mask.sum() == 0:
        return canvas
    img = Image.fromarray(px[:, :, :3].copy(), "RGB")
    # Only quantize opaque pixels: put them in a strip, quantize, write back.
    pts = px[mask][:, :3]
    strip = Image.fromarray(pts.reshape(1, -1, 3).astype(np.uint8), "RGB")
    q = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = np.array(q).reshape(-1, 3)
    if keep_dark:
        # Snap the darkest cluster to a near-black outline colour.
        lum = out.sum(axis=1)
        darkest = out[np.argmin(lum)]
        out[np.all(out == darkest, axis=1)] = [24, 20, 32]
    px[mask, :3] = out
    _ = img
    return canvas


# ------------------------------------------------------------------ pixel font (5x7 in 6x8 cells)
FONT = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "10001", "11001", "10101", "10011", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "a": ["00000", "00000", "01110", "00001", "01111", "10001", "01111"],
    "b": ["10000", "10000", "11110", "10001", "10001", "10001", "11110"],
    "c": ["00000", "00000", "01110", "10000", "10000", "10001", "01110"],
    "d": ["00001", "00001", "01111", "10001", "10001", "10001", "01111"],
    "e": ["00000", "00000", "01110", "10001", "11111", "10000", "01110"],
    "f": ["00110", "01001", "01000", "11100", "01000", "01000", "01000"],
    "g": ["00000", "01111", "10001", "10001", "01111", "00001", "01110"],
    "h": ["10000", "10000", "10110", "11001", "10001", "10001", "10001"],
    "i": ["00100", "00000", "01100", "00100", "00100", "00100", "01110"],
    "j": ["00010", "00000", "00110", "00010", "00010", "10010", "01100"],
    "k": ["10000", "10000", "10010", "10100", "11000", "10100", "10010"],
    "l": ["01100", "00100", "00100", "00100", "00100", "00100", "01110"],
    "m": ["00000", "00000", "11010", "10101", "10101", "10101", "10001"],
    "n": ["00000", "00000", "10110", "11001", "10001", "10001", "10001"],
    "o": ["00000", "00000", "01110", "10001", "10001", "10001", "01110"],
    "p": ["00000", "11110", "10001", "10001", "11110", "10000", "10000"],
    "q": ["00000", "01111", "10001", "10001", "01111", "00001", "00001"],
    "r": ["00000", "00000", "10110", "11001", "10000", "10000", "10000"],
    "s": ["00000", "00000", "01111", "10000", "01110", "00001", "11110"],
    "t": ["01000", "01000", "11100", "01000", "01000", "01001", "00110"],
    "u": ["00000", "00000", "10001", "10001", "10001", "10011", "01101"],
    "v": ["00000", "00000", "10001", "10001", "10001", "01010", "00100"],
    "w": ["00000", "00000", "10001", "10001", "10101", "10101", "01010"],
    "x": ["00000", "00000", "10001", "01010", "00100", "01010", "10001"],
    "y": ["00000", "10001", "10001", "10001", "01111", "00001", "01110"],
    "z": ["00000", "00000", "11111", "00010", "00100", "01000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    " ": ["00000"] * 7,
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ",": ["00000", "00000", "00000", "00000", "01100", "00100", "01000"],
    "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
    "'": ["00100", "00100", "01000", "00000", "00000", "00000", "00000"],
    "\"": ["01010", "01010", "00000", "00000", "00000", "00000", "00000"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    ";": ["00000", "01100", "01100", "00000", "01100", "00100", "01000"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    "(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
    ")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "=": ["00000", "00000", "11111", "00000", "11111", "00000", "00000"],
    "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
    "&": ["01100", "10010", "10100", "01000", "10101", "10010", "01101"],
    "*": ["00000", "10101", "01110",
          "11111", "01110", "10101", "00000"],
    "#": ["01010", "01010", "11111", "01010", "11111", "01010", "01010"],
    "_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
    "<": ["00010", "00100", "01000", "10000", "01000", "00100", "00010"],
    ">": ["01000", "00100", "00010", "00001", "00010", "00100", "01000"],
    "[": ["01110", "01000", "01000", "01000", "01000", "01000", "01110"],
    "]": ["01110", "00010", "00010", "00010", "00010", "00010", "01110"],
    # Special glyphs mapped to otherwise unused ASCII
    "^": ["00000", "00100", "01110", "11111", "00000", "00000", "00000"],   # up arrow
    "~": ["00000", "00000", "11111", "01110", "00100", "00000", "00000"],   # down arrow (more text)
    "@": ["01000", "01100", "01110", "01111", "01110", "01100", "01000"],   # menu cursor
    "`": ["00000", "01110", "10001", "10001", "10001", "01110", "00000"],   # ring symbol
    "|": ["01010", "11111", "11111", "11111", "01110", "00100", "00000"],   # heart
    "$": ["00100", "01111", "10100", "01110", "00101", "11110", "00100"],
}
FONT_FIRST = 32
FONT_COLS = 16


def build_font():
    chars = [chr(i) for i in range(32, 127)]
    rows = (len(chars) + FONT_COLS - 1) // FONT_COLS
    img = Canvas(FONT_COLS * 6, rows * 8)
    widths = {}
    for i, ch in enumerate(chars):
        g = FONT.get(ch, FONT["?"])
        x0, y0 = (i % FONT_COLS) * 6, (i // FONT_COLS) * 8
        w = 0
        for y, row in enumerate(g):
            for x, bit in enumerate(row):
                if bit == "1":
                    img.put(x0 + x, y0 + y, (255, 255, 255, 255))
                    w = max(w, x + 1)
        widths[ch] = 6
    save(img, "font.png")
    with open(os.path.join(ART, "font.json"), "w") as f:
        json.dump({"cell": [6, 8], "columns": FONT_COLS, "first": FONT_FIRST}, f)


Canvas = M.Canvas


# ------------------------------------------------------------------ tiles

def noise_marks(c, col, n, seed, shape="blade"):
    r = np.random.default_rng(seed)
    for _ in range(n):
        x, y = int(r.integers(1, T - 2)), int(r.integers(2, T - 1))
        if shape == "blade":
            c.put(x, y, col)
            c.put(x + 1, y - 1, col)
        else:
            c.put(x, y, col)


def t_grass(v=0):
    p = pal("grass")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, p[1])
    if v == 0:
        for x, y in [(3, 4), (10, 2), (6, 10), (13, 11), (1, 13)]:
            c.put(x, y, p[2])
            c.put(x + 1, y - 1, p[2])
    else:
        for x, y in [(2, 3), (11, 6), (5, 12), (14, 1)]:
            c.put(x, y, p[2])
            c.put(x + 1, y - 1, p[2])
            c.put(x + 2, y, p[2])
        c.put(8, 8, p[0])
    return c


def t_flowers(frame=0):
    c = t_grass(1)
    p = pal("flower")
    for (x, y) in [(3, 3), (11, 10)]:
        dx = frame
        for ox, oy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            c.put(x + ox + dx, y + oy, p[2] if (ox + oy) % 2 else p[1])
        c.put(x + dx, y, p[0])
    return c


def t_tall_grass(frame=0):
    p = pal("grass")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, p[1])
    for row in range(2):
        y0 = 2 + row * 8
        for i in range(4):
            x = i * 4 + (2 if row else 0) + (1 if frame and row == 0 else 0)
            c.poly([(x, y0 + 6), (x + 1, y0), (x + 2, y0 + 3), (x + 3, y0 - 1), (x + 4, y0 + 6)], p[2])
            c.put(x + 1, y0 + 2, p[0])
            c.put(x + 3, y0 + 1, p[0])
            c.hline(x, x + 3, y0 + 6, p[3])
    return c


def t_tall_grass_top():
    """Upper half of tall grass blades: drawn over a character's legs."""
    full = t_tall_grass(0)
    c = Canvas(T, T)
    c.px[8:, :] = full.px[8:, :]
    # keep only blade pixels (not the flat ground) so feet hide in the grass
    p = pal("grass")
    m = np.all(c.px[:, :, :3] == p[1][:3], axis=2)
    c.px[m] = 0
    return c


def t_path(v=0):
    p = pal("path")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, p[1])
    for x, y in [(2, 3), (9, 6), (5, 12), (13, 13), (12, 2)][: 5 - v * 2]:
        c.put(x, y, p[2])
        c.put(x + 1, y, p[0])
    return c


def t_sand():
    p = pal("sand")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, p[1])
    for x, y in [(3, 2), (11, 5), (6, 10), (14, 12), (1, 14)]:
        c.put(x, y, p[2])
    return c


def t_water(mask=15, frame=0):
    p = pal("water")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, p[2])
    for i in range(3):
        y = 2 + i * 5
        x = (i * 6 + frame * 2) % T
        c.hline(x, min(T - 1, x + 3), y, p[1])
        c.put((x + 9) % T, y + 2, p[3])
    n, e, s, w = bool(mask & 1), bool(mask & 2), bool(mask & 4), bool(mask & 8)
    shore = pal("sand")
    if not n:
        c.rect(0, 0, T - 1, 2, shore[1])
        c.hline(0, T - 1, 3, p[0])
    if not s:
        c.rect(0, T - 3, T - 1, T - 1, shore[1])
        c.hline(0, T - 1, T - 4, p[0])
    if not w:
        c.rect(0, 0, 2, T - 1, shore[1])
        c.vline(3, 0, T - 1, p[0])
    if not e:
        c.rect(T - 3, 0, T - 1, T - 1, shore[1])
        c.vline(T - 4, 0, T - 1, p[0])
    return c


def t_tree():
    """Classic round GBC tree filling a 16x16 tile (solid)."""
    p = pal("tree")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, pal("grass")[1])
    c.ellipse(8, 6.5, 7.6, 6.6, p[3])
    c.ellipse(8, 6.2, 6.6, 5.6, p[2])
    c.ellipse(7, 5, 4.6, 3.6, p[1])
    for x, y in [(5, 3), (8, 4), (4, 6), (10, 7)]:
        c.put(x, y, p[0])
    c.rect(6, 12, 9, 15, hexc("704020"))
    c.vline(9, 12, 15, p[3])
    c.vline(6, 12, 15, hexc("a06838"))
    return c


def t_ledge():
    """One-way ledge: you can hop down (south) but not climb up."""
    c = t_grass(0)
    p = pal("grass")
    r = pal("rock")
    c.rect(0, 9, T - 1, 12, r[1])
    c.hline(0, T - 1, 9, r[0])
    c.hline(0, T - 1, 12, r[3])
    for x in (3, 8, 13):
        c.put(x, 11, r[2])
    c.rect(0, 13, T - 1, T - 1, p[2])
    return c


def t_fence():
    w = pal("wood")
    c = t_grass(0)
    for x in (1, 13):
        c.rect(x, 3, x + 2, 14, w[1])
        c.vline(x + 2, 3, 14, w[3])
        c.hline(x, x + 2, 3, w[0])
    c.rect(0, 6, T - 1, 7, w[1])
    c.rect(0, 10, T - 1, 11, w[1])
    c.hline(0, T - 1, 8, w[3])
    c.hline(0, T - 1, 12, w[3])
    return c


def t_rock_wall(top=False):
    r = pal("rock")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, r[1])
    for y in (4, 9, 14):
        c.hline(0, T - 1, y, r[2])
    for x, y in [(4, 0), (11, 5), (6, 10), (2, 5), (13, 10)]:
        c.vline(x, y, y + 3, r[2])
        c.put(x + 1, y + 1, r[0])
    if top:
        g = pal("grass")
        c.rect(0, 0, T - 1, 3, g[1])
        c.hline(0, T - 1, 4, r[3])
    return c


def t_stone():
    s = pal("stone")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, s[1])
    c.hline(0, T - 1, 7, s[2])
    c.hline(0, T - 1, 15, s[2])
    c.vline(7, 0, 7, s[2])
    c.vline(15, 8, 15, s[2])
    c.hline(0, 6, 0, s[0])
    c.hline(8, 14, 8, s[0])
    return c


def t_floor():
    f = pal("floor")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, f[1])
    for y in (3, 7, 11, 15):
        c.hline(0, T - 1, y, f[2])
    for x, y in [(5, 0), (12, 4), (2, 8), (9, 12)]:
        c.vline(x, y, y + 2, f[2])
    return c


def t_inwall(window=False):
    w = pal("inwall")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, w[1])
    c.rect(0, 12, T - 1, T - 1, w[2])
    c.hline(0, T - 1, 11, w[3])
    if window:
        c.rect(3, 2, 12, 9, w[3])
        c.rect(4, 3, 11, 8, hexc("a8e0f8"))
        c.vline(7, 3, 8, w[3])
        c.hline(4, 11, 5, w[3])
        c.put(5, 4, hexc("ffffff"))
    else:
        c.vline(5, 0, 10, w[0])
        c.vline(12, 0, 10, w[0])
    return c


def t_mat():
    c = t_floor()
    r = pal("roof_red")
    c.rect(1, 4, 14, 12, r[2])
    c.rect(2, 5, 13, 11, r[1])
    c.hline(3, 12, 8, r[0])
    return c


def t_counter():
    w = pal("wood")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, w[2])
    c.rect(0, 0, T - 1, 5, w[1])
    c.hline(0, T - 1, 0, w[0])
    c.hline(0, T - 1, 6, w[3])
    c.vline(7, 7, T - 1, w[3])
    return c


def t_shelf():
    w = pal("wood")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, w[3])
    c.rect(1, 1, T - 2, T - 2, w[2])
    books = [hexc("c04830"), hexc("3868c8"), hexc("488838"), hexc("e0b070")]
    for row, y in enumerate((2, 9)):
        c.hline(1, T - 2, y + 5, w[3])
        for i in range(6):
            c.rect(2 + i * 2, y, 2 + i * 2, y + 4, books[(i + row) % 4])
    return c


def t_bed():
    c = t_floor()
    c.rect(1, 1, 14, 15, hexc("482810"))
    c.rect(2, 2, 13, 5, hexc("f8f8f0"))
    c.rect(2, 6, 13, 14, hexc("3868c8"))
    c.hline(2, 13, 6, hexc("88b8f0"))
    return c


def t_plant():
    c = t_floor()
    c.rect(5, 10, 10, 15, hexc("c04830"))
    c.hline(5, 10, 10, hexc("f08858"))
    t = pal("tree")
    c.ellipse(8, 6, 5.5, 5, t[3])
    c.ellipse(8, 5.6, 4.6, 4, t[2])
    c.put(6, 4, t[1])
    c.put(9, 3, t[1])
    return c


def t_table():
    c = t_floor()
    w = pal("wood")
    c.rect(1, 3, 14, 10, w[1])
    c.hline(1, 14, 3, w[0])
    c.hline(1, 14, 10, w[3])
    c.rect(2, 11, 3, 14, w[3])
    c.rect(12, 11, 13, 14, w[3])
    return c


def t_altar():
    """The ring-sage's altar with three rings (starter choice)."""
    c = t_table()
    g = pal("glow")
    for x in (3, 7, 11):
        c.ellipse(x + 1, 6, 1.6, 1.6, hexc("f0c040"))
        c.put(x + 1, 6, g[1])
    return c


def t_rug():
    c = t_floor()
    b = pal("roof_blue")
    c.rect(0, 0, T - 1, T - 1, b[2])
    c.rect(2, 2, T - 3, T - 3, b[1])
    c.put(7, 7, b[0])
    c.put(8, 8, b[0])
    return c


def t_stairs():
    s = pal("stone")
    c = Canvas(T, T)
    for i in range(4):
        c.rect(0, i * 4, T - 1, i * 4 + 3, s[1 + (i % 2)])
        c.hline(0, T - 1, i * 4 + 3, s[3])
    return c


def t_cave_floor():
    r = pal("rock")
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, r[2])
    for x, y in [(3, 4), (11, 9), (6, 13)]:
        c.put(x, y, r[3])
        c.put(x + 1, y, r[1])
    return c


def t_black():
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, hexc("101018"))
    return c


TILES = {}


def build_tiles():
    tiles = []

    def add(name, canvas):
        TILES[name] = len(tiles)
        tiles.append(canvas)
    add("grass", t_grass(0))
    add("grass2", t_grass(1))
    add("flowers", t_flowers(0))
    add("flowers_b", t_flowers(1))
    add("tallgrass", t_tall_grass(0))
    add("tallgrass_b", t_tall_grass(1))
    add("path", t_path(0))
    add("path2", t_path(1))
    add("sand", t_sand())
    add("tree", t_tree())
    add("ledge", t_ledge())
    add("fence", t_fence())
    add("rock", t_rock_wall(False))
    add("rock_top", t_rock_wall(True))
    add("stone", t_stone())
    add("floor", t_floor())
    add("inwall", t_inwall(False))
    add("inwall_window", t_inwall(True))
    add("mat", t_mat())
    add("counter", t_counter())
    add("shelf", t_shelf())
    add("bed", t_bed())
    add("plant", t_plant())
    add("table", t_table())
    add("altar", t_altar())
    add("rug", t_rug())
    add("stairs", t_stairs())
    add("cave", t_cave_floor())
    add("black", t_black())
    # Water: 16 shore masks x 2 animation frames; frame 2 sits one row below.
    while len(tiles) % 16:
        add("pad%d" % len(tiles), Canvas(T, T))
    for f in range(2):
        for m in range(16):
            add("water%d_%d" % (f, m), t_water(m, f))
    atlas = Canvas(16 * T, ((len(tiles) + 15) // 16) * T)
    for i, t in enumerate(tiles):
        quantize(t, 4, keep_dark=False)
        atlas.paste(t, (i % 16) * T, (i // 16) * T)
    save(atlas, "tiles.png")
    with open(os.path.join(ART, "tiles.json"), "w") as f:
        json.dump({"tile_size": T, "columns": 16, "tiles": TILES}, f, indent=1)
    return atlas


# ------------------------------------------------------------------ buildings & props (objects)

def building(roof="roof_red", w_tiles=4, h_tiles=4, sign=None, door_x=None):
    W, H = w_tiles * T, h_tiles * T
    r = pal(roof)
    wl = pal("wall")
    c = Canvas(W, H)
    roof_h = H // 2 + 2
    # Roof with shingle rows
    c.rect(0, 2, W - 1, roof_h, r[2])
    for y in range(4, roof_h, 4):
        c.hline(1, W - 2, y, r[1])
        for x in range(2 + (y // 4 % 2) * 3, W - 2, 6):
            c.put(x, y + 1, r[3])
    c.hline(2, W - 3, 1, r[1])
    c.hline(0, W - 1, roof_h, r[3])
    c.hline(0, W - 1, roof_h + 1, r[3])
    # Walls
    c.rect(2, roof_h + 2, W - 3, H - 1, wl[1])
    c.vline(2, roof_h + 2, H - 1, wl[3])
    c.vline(W - 3, roof_h + 2, H - 1, wl[3])
    c.hline(2, W - 3, H - 1, wl[3])
    # Door
    dx = (door_x if door_x is not None else w_tiles // 2) * T + 3
    c.rect(dx, H - 12, dx + 9, H - 1, wl[3])
    c.rect(dx + 1, H - 11, dx + 8, H - 1, hexc("704020"))
    c.vline(dx + 4, H - 11, H - 1, hexc("482810"))
    # Windows
    for wx in range(6, W - 10, 18):
        if abs(wx - dx) < 12:
            continue
        c.rect(wx, roof_h + 5, wx + 8, roof_h + 11, wl[3])
        c.rect(wx + 1, roof_h + 6, wx + 7, roof_h + 10, hexc("a8e0f8"))
        c.put(wx + 2, roof_h + 7, hexc("ffffff"))
    if sign:
        sx = dx + 13
        c.rect(sx, roof_h + 4, sx + 9, roof_h + 10, wl[3])
        c.rect(sx + 1, roof_h + 5, sx + 8, roof_h + 9, sign)
    return c


def prop_sign():
    w = pal("wood")
    c = Canvas(T, T)
    c.rect(2, 3, 13, 10, w[3])
    c.rect(3, 4, 12, 9, w[1])
    c.hline(4, 11, 6, w[2])
    c.rect(7, 11, 8, 15, w[3])
    return c


def prop_ring_stone(frame=0):
    s = pal("stone")
    g = pal("glow")
    c = Canvas(T, 24)
    c.poly([(3, 23), (4, 6), (8, 1), (12, 6), (13, 23)], s[3])
    c.poly([(4, 22), (5, 7), (8, 3), (11, 7), (12, 22)], s[1])
    c.vline(11, 8, 22, s[2])
    c.ellipse(8, 11, 2.6, 2.6, g[2] if frame else g[1])
    c.put(8, 11, g[0])
    c.vline(8, 15, 20, g[1 + frame])
    return c


def prop_item():
    """A glinting item on the ground (a ring in a cloth bundle)."""
    c = Canvas(T, T)
    c.ellipse(8, 10, 5, 3.4, hexc("181820"))
    c.ellipse(8, 9.6, 4, 2.6, hexc("c04830"))
    c.ellipse(8, 8.5, 2.2, 2.2, hexc("f0c040"))
    c.put(8, 8, hexc("ffffff"))
    return c


def prop_tent(name="tent"):
    p = pal(name)
    c = Canvas(32, 32)
    c.poly([(0, 31), (16, 3), (31, 31)], p[3])
    c.poly([(2, 30), (16, 6), (29, 30)], p[1])
    c.poly([(16, 6), (29, 30), (20, 30)], p[2])
    c.poly([(12, 31), (16, 18), (20, 31)], hexc("201008"))
    c.vline(16, 0, 5, p[3])
    return c


def prop_campfire(frame=0):
    f = pal("fire")
    c = Canvas(T, T)
    c.rect(3, 12, 12, 14, hexc("482810"))
    c.line(3, 14, 12, 11, hexc("704020"))
    h = 7 + frame
    c.poly([(4, 12), (8, 12 - h), (12, 12)], f[2])
    c.poly([(6, 12), (8, 14 - h), (10, 12)], f[1])
    c.poly([(7, 12), (8, 8), (9, 12)], f[0])
    return c


def prop_lore_stone():
    s = pal("stone")
    g = pal("glow")
    c = Canvas(T, 20)
    c.poly([(2, 19), (3, 3), (8, 0), (13, 3), (14, 19)], s[3])
    c.poly([(3, 18), (4, 4), (8, 1), (12, 4), (13, 18)], s[2])
    for y in (6, 9, 12, 15):
        c.hline(5, 11, y, g[1])
    return c


def prop_banner(col="c04830"):
    c = Canvas(T, 24)
    c.vline(3, 0, 23, hexc("482810"))
    c.rect(4, 1, 13, 14, hexc("181820"))
    c.rect(5, 2, 12, 13, hexc(col))
    c.ellipse(8.5, 7, 2.4, 2.4, hexc("f0c040"))
    c.ellipse(8.5, 7, 1.0, 1.0, hexc(col))
    return c


def prop_crate():
    w = pal("wood")
    c = Canvas(T, T)
    c.rect(1, 2, 14, 15, w[3])
    c.rect(2, 3, 13, 14, w[1])
    c.line(2, 3, 13, 14, w[2])
    c.line(13, 3, 2, 14, w[2])
    c.hline(2, 13, 3, w[0])
    return c


# ------------------------------------------------------------------ characters

def ow_spec(base):
    """Converts a make_art character spec to 16x16 overworld proportions."""
    sp = dict(base)
    big = base.get("w", 16) > 16
    sp.update(w=16, h=16, head_w=10, head_h=8, torso_w=8 if not big else 10, torso_h=4 if not big else 5,
              leg_h=2 if base.get("robe") else 3, arm=2)
    if base.get("robe"):
        sp.update(head_w=11, torso_h=4)
    if "gouran" in str(base.get("hood")) or base.get("belly"):
        sp.update(head_w=11)
    sp["beard_len"] = min(base.get("beard_len", 2), 2)
    return sp


OW_FACINGS = ["down", "up", "left", "right"]
OW_FRAMES = [0, 1, 3]   # stand, step A, step B (make_art frame ids)


def ow_sheet(sp):
    """Rows: down, up, left, right. Columns: stand, step A, step B."""
    sheet = Canvas(16 * 3, 16 * 4)
    for r, facing in enumerate(OW_FACINGS):
        for k, f in enumerate(OW_FRAMES):
            if facing == "right":
                img = M.draw_char(sp, "left", f).flipped()
            else:
                img = M.draw_char(sp, facing, f)
            quantize(img, 4)
            sheet.paste(img, k * 16, r * 16)
    return sheet


OW = {}


# The hero: an Emoria Guild warrior (fixed design, like classic handheld RPGs).
PLAYER = M.base_spec(skin=hexc("f0b888"), hair=hexc("6b4430"), top=hexc("3868c8"), top2=hexc("f0c040"),
                     pants=hexc("483828"), cloak=hexc("c04830"), belt=hexc("f0c040"), brow=False)


def build_characters():
    C = M.CHARACTERS
    specs = {
        "player": PLAYER, "warden": C["human_warden"], "villager": C["human_villager"],
        "villager2": C["human_villager2"], "amir": C["amir"], "burrok": C["burrok"], "vapouriun": C["vapouriun"],
        "gouran": C["gouran"], "gyria": C["gyria"], "gyria_archer": C["gyria_archer"], "gyria_boss": C["gyria_boss"],
        "kesh": C["gyria_kesh"],
    }
    for name, base in specs.items():
        sp = ow_spec(base)
        if name == "burrok" or name == "gyria_boss":
            # Big peoples get a 16x24 sprite (they tower over others on the map).
            sp.update(w=16, h=22, head_w=11, head_h=9, torso_w=12, torso_h=6, leg_h=4, arm=3)
            sheet = Canvas(16 * 3, 22 * 4)
            for r, facing in enumerate(OW_FACINGS):
                for k, f in enumerate(OW_FRAMES):
                    img = M.draw_char(sp, "left", f).flipped() if facing == "right" else M.draw_char(sp, facing, f)
                    quantize(img, 4)
                    sheet.paste(img, k * 16, r * 22)
            save(sheet, "chars/%s.png" % name)
            OW[name] = sheet
            continue
        sheet = ow_sheet(sp)
        save(sheet, "chars/%s.png" % name)
        OW[name] = sheet


# ------------------------------------------------------------------ battle sprites

def battle_trainer_back():
    """The warrior seen from behind, drawn at 24 px and shown at 2x like GB back sprites."""
    sp = dict(PLAYER)
    sp.update(w=24, h=24, head_w=12, head_h=10, torso_w=14, torso_h=8, leg_h=4, arm=3)
    img = M.draw_char(sp, "up", 0)
    steel = hexc("e0e8f0")
    for i in range(10):
        img.put(19 + i // 3, 15 - i, steel)
    img.rect(17, 14, 20, 15, hexc("f0c040"))
    img.darken_outline(0.5)
    return quantize(img, 4)


def battle_fighter_front(name, size=28, weapon="hookblade"):
    """A Gyria fighter facing you, drawn small and shown at 2x."""
    sp = dict(M.CHARACTERS[name])
    sp.update(w=size, h=size, head_w=int(size * 0.46), head_h=int(size * 0.38), torso_w=int(size * 0.48),
              torso_h=int(size * 0.28), leg_h=int(size * 0.16), arm=max(3, size // 9))
    img = M.draw_char(sp, "down", 4)
    steel = hexc("e0e8f0")
    h = size // 2
    if weapon == "hookblade":
        for i in range(9):
            img.put(size - 6 + i // 4, h + 3 - i, steel)
        img.rect(size - 6, h - 7, size - 4, h - 6, steel)
    elif weapon == "axe":
        img.vline(size - 5, h - 9, h + 6, hexc("704020"))
        img.poly([(size - 5, h - 10), (size, h - 8), (size, h - 2), (size - 5, h - 4)], steel)
    elif weapon == "bow":
        for i in range(-8, 9):
            img.put(size - 4 + int((64 - i * i) ** 0.5 * 0.35), h + i, hexc("704020"))
        img.vline(size - 4, h - 8, h + 8, hexc("f0f0f0"))
    img.darken_outline(0.5)
    return quantize(img, 4)


def build_battle():
    save(battle_trainer_back(), "battle/trainer.png")
    save(battle_fighter_front("gyria", 28, "hookblade"), "battle/gyria.png")
    save(battle_fighter_front("gyria_archer", 28, "bow"), "battle/gyria_archer.png")
    save(battle_fighter_front("gyria_boss", 32, "axe"), "battle/gyria_boss.png")
    for kind in M.CREATURES:
        save(quantize(M.draw_creature(kind, "front", 48), 4), "battle/%s_front.png" % kind)
        save(quantize(M.draw_creature(kind, "back", 48), 4), "battle/%s_back.png" % kind)
        small = Canvas(32, 16)
        small.paste(quantize(M.draw_creature(kind, "front", 16, 0), 4), 0, 0)
        small.paste(quantize(M.draw_creature(kind, "front", 16, 1), 4), 16, 0)
        save(small, "battle/%s_small.png" % kind)


# ------------------------------------------------------------------ UI

def ui_frame():
    """9-slice text box frame (24x24, 8 px corners), GB style double border."""
    u = pal("ui")
    c = Canvas(24, 24)
    c.rect(0, 0, 23, 23, u[0])
    c.rect(1, 1, 22, 22, u[3])
    c.rect(2, 2, 21, 21, u[0])
    c.rect(3, 3, 20, 20, u[3])
    c.rect(4, 4, 19, 19, u[0])
    for x, y in ((1, 1), (22, 1), (1, 22), (22, 22)):
        c.put(x, y, u[0])
    return c


def build_ui():
    save(ui_frame(), "ui/frame.png")
    p = Canvas(16, 16)
    p.ellipse(8, 8, 6, 6, hexc("f0c040"))
    p.ellipse(8, 8, 3.5, 3.5, (0, 0, 0, 0))
    p.put(8, 2, hexc("a8f0ff"))
    p.put(7, 2, hexc("ffffff"))
    save(p, "ui/ring.png")
    ex = Canvas(16, 16)
    ex.rect(5, 0, 10, 15, hexc("181818"))
    ex.rect(6, 1, 9, 9, hexc("f8f8f8"))
    ex.rect(6, 11, 9, 14, hexc("f8f8f8"))
    save(ex, "ui/exclaim.png")


# ------------------------------------------------------------------ main

def save(canvas, rel):
    path = os.path.join(ART, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    canvas.image().save(path)


def main():
    if os.path.isdir(ART):
        shutil.rmtree(ART)
    os.makedirs(ART)
    build_font()
    atlas = build_tiles()
    build_characters()
    build_battle()
    build_ui()
    props = {
        "house_red": building("roof_red", 4, 4), "house_green": building("roof_green", 4, 4),
        "guild_hall": building("roof_blue", 6, 5, sign=hexc("3868c8")), "shop": building("roof_red", 4, 4, sign=hexc("f0c040")),
        "sign": prop_sign(), "ring_stone0": prop_ring_stone(0), "ring_stone1": prop_ring_stone(1), "item": prop_item(),
        "tent": prop_tent("tent"), "tent_red": prop_tent("tent_red"), "campfire0": prop_campfire(0),
        "campfire1": prop_campfire(1), "lore_stone": prop_lore_stone(), "banner": prop_banner(), "crate": prop_crate(),
    }
    for name, cv in props.items():
        if name.startswith(("house", "guild", "shop", "tent")):
            quantize(cv, 4, keep_dark=False) if not name.startswith(("house", "guild", "shop")) else None
        save(cv, "objects/%s.png" % name)
    if "--preview" in sys.argv:
        preview(atlas, props)
    print("GBC art written to", os.path.relpath(ART, ROOT))


def preview(atlas, props):
    out = os.path.join(HERE, "art_preview")
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, ".gdignore"), "w").close()
    W, H = 320, 288
    bg = Image.new("RGBA", (W, H), (248, 248, 240, 255))
    bg.alpha_composite(atlas.image().crop((0, 0, 256, 64)), (0, 0))
    x = 0
    y = 70
    for name in ["player", "warden", "amir", "burrok", "vapouriun", "gouran", "gyria", "gyria_boss", "kesh", "villager"]:
        im = OW[name].image()
        fw = 16
        fh = im.height // 4
        for k in range(4):
            bg.alpha_composite(im.crop((0, k * fh, fw, (k + 1) * fh)), (x + k * 17, y))
        x += 70
        if x > W - 70:
            x = 0
            y += 26
    y += 30
    bx = 0
    for f in ["trainer", "gyria", "gyria_boss", "alpha_front", "beta_front", "gamma_front", "alpha_back"]:
        im = Image.open(os.path.join(ART, "battle", f + ".png"))
        if im.width < 40:
            im = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        if bx + im.width > W:
            bx = 0
            y += 60
        bg.alpha_composite(im, (bx, y))
        bx += im.width + 4
    y += 62
    px = 0
    for name in ["house_red", "guild_hall", "ring_stone0", "sign", "tent", "lore_stone", "item", "campfire0"]:
        im = props[name].image()
        if px + im.width > W:
            px = 0
            y += 82
        bg.alpha_composite(im, (px, y))
        px += im.width + 4
    bg.resize((W * 3, H * 3), Image.NEAREST).save(os.path.join(out, "gbc_sheet.png"))


if __name__ == "__main__":
    main()
