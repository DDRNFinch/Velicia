#!/usr/bin/env python3
"""Generates Velicia's original pixel art (16 px tiles, chibi characters,
creatures, effects and UI) into res://art/.

Everything is drawn from code so the art is original and consistent, and can
be regenerated or tweaked in one place. Run:  python3 tools/make_art.py
(needs numpy + Pillow). Preview sheets go to tools/art_preview/ (ignored by
Godot) when --preview is passed.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
ART = os.path.join(ROOT, "art")
rng = np.random.default_rng(7)


# ------------------------------------------------------------------ canvas helpers

def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, k):
    """k > 0 lightens, k < 0 darkens (multiplicative toward white/black)."""
    r, g, b, a = c
    if k >= 0:
        return (int(r + (255 - r) * k), int(g + (255 - g) * k), int(b + (255 - b) * k), a)
    k = -k
    return (int(r * (1 - k)), int(g * (1 - k)), int(b * (1 - k)), a)


def hue_shift_dark(c, k):
    """Darker shade that drifts toward blue/purple, the classic pixel-art ramp."""
    r, g, b, a = shade(c, -k)
    return (int(r * 0.92), int(g * 0.95), min(255, int(b * 1.05 + 12 * k)), a)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), np.uint8)

    def put(self, x, y, c):
        if c is None:
            return
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y, x] = c

    def get(self, x, y):
        return tuple(self.px[y, x])

    def rect(self, x0, y0, x1, y1, c):
        """Inclusive rectangle."""
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.put(x, y, c)

    def hline(self, x0, x1, y, c):
        self.rect(x0, y, x1, y, c)

    def vline(self, x, y0, y1, c):
        self.rect(x, y0, x, y1, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x + 0.5 - cx) / max(rx, 0.01)) ** 2 + ((y + 0.5 - cy) / max(ry, 0.01)) ** 2 <= 1.0:
                    self.put(x, y, c)

    def poly(self, pts, c):
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)), int(max(ys)) + 1):
            for x in range(int(min(xs)), int(max(xs)) + 1):
                if point_in_poly(x + 0.5, y + 0.5, pts):
                    self.put(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n + 1):
            t = i / max(n, 1)
            self.put(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), c)

    def outline(self, c=(24, 20, 30, 255), only_outside=True):
        """Adds a 1 px dark outline around opaque pixels (selective-outline look)."""
        a = self.px[:, :, 3] > 0
        out = np.zeros_like(a)
        out[1:, :] |= a[:-1, :]
        out[:-1, :] |= a[1:, :]
        out[:, 1:] |= a[:, :-1]
        out[:, :-1] |= a[:, 1:]
        edge = out & ~a
        self.px[edge] = c

    def darken_outline(self, k=0.55):
        """Outline that takes a dark tone of the neighbouring colour (softer, Pokémon-like)."""
        a = self.px[:, :, 3] > 0
        src = self.px.copy()
        for y in range(self.h):
            for x in range(self.w):
                if a[y, x]:
                    continue
                best = None
                for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < self.w and 0 <= yy < self.h and a[yy, xx]:
                        best = tuple(src[yy, xx])
                        break
                if best is not None:
                    r, g, b, _ = best
                    self.px[y, x] = (int(r * (1 - k) * 0.6 + 10), int(g * (1 - k) * 0.55 + 8), int(b * (1 - k) * 0.7 + 18), 255)

    def paste(self, other, x, y):
        for yy in range(other.h):
            for xx in range(other.w):
                c = other.px[yy, xx]
                if c[3] > 0:
                    self.put(x + xx, y + yy, tuple(c))

    def flipped(self):
        c = Canvas(self.w, self.h)
        c.px = self.px[:, ::-1].copy()
        return c

    def image(self):
        return Image.fromarray(self.px, "RGBA")


def point_in_poly(x, y, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi:
            inside = not inside
        j = i
    return inside


OUTLINE = (34, 26, 40, 255)


# ------------------------------------------------------------------ palettes

SKIN = {
    "light": hexc("f2c9a6"), "tan": hexc("dba47c"), "brown": hexc("b07850"),
    "dark": hexc("7d5036"), "deep": hexc("5a3826"),
    "vapour": hexc("4f8fc6"), "gyria": hexc("74a548"), "gyria_dark": hexc("5c8a3a"),
}
HAIR = {
    "black": hexc("2c2430"), "brown": hexc("6b4430"), "chestnut": hexc("9a5a30"),
    "blond": hexc("e0b860"), "red": hexc("b0482c"), "white": hexc("e6e2dc"), "grey": hexc("a8a4a0"),
    "wolf": hexc("8c8278"), "bear": hexc("7a5234"), "teal": hexc("2e6a7a"),
}


# ------------------------------------------------------------------ characters
#
# A character is drawn by draw_char(spec, facing, frame) on a canvas whose size
# depends on the people's scale. facing: "down", "up", "left" (right = mirror).
# frame: 0 idle, 1 step A, 2 idle-b, 3 step B, 4 attack wind, 5 attack strike,
# 6 hurt.

FRAMES = ["idle", "stepA", "idle2", "stepB", "wind", "strike", "hurt"]
FACINGS = ["down", "left", "right", "up"]


def base_spec(**kw):
    s = dict(
        w=16, h=24, head_w=10, head_h=9, torso_w=10, torso_h=6, leg_h=5, arm=2,
        skin=SKIN["tan"], hair=HAIR["brown"], hair_style="short", eyes=(40, 30, 40, 255),
        top=hexc("5a6e9a"), top2=None, pants=hexc("4a4038"), boots=hexc("5a3a28"), belt=hexc("8a6a3a"),
        cloak=None, robe=None, hood=None, ears=None, tail=None, beard=None, tusks=False, fins=False,
        scales=False, arm_fur=None, claws=False, paws=False, belly=0, weapon=None, brow=False,
        pauldrons=None, iris=None,
    )
    s.update(kw)
    return s


def draw_char(sp, facing, frame):
    W, H = sp["w"], sp["h"]
    c = Canvas(W, H)
    cx = W // 2
    step = {1: 1, 3: -1}.get(frame, 0)
    bob = 1 if frame in (1, 3) else 0
    hurt = frame == 6
    hw, hh = sp["head_w"], sp["head_h"]
    tw, th = sp["torso_w"], sp["torso_h"]
    lh = sp["leg_h"]
    skin = sp["skin"]
    skin_d = hue_shift_dark(skin, 0.22)
    skin_l = shade(skin, 0.18)
    top = sp["top"]
    top_d = hue_shift_dark(top, 0.25)
    top_l = shade(top, 0.15)
    pants = sp["pants"]
    pants_d = hue_shift_dark(pants, 0.25)
    boots = sp["boots"]
    hair = sp["hair"]
    hair_d = hue_shift_dark(hair, 0.28)
    hair_l = shade(hair, 0.2)

    foot_y = H - 1
    leg_top = foot_y - lh + 1
    torso_bot = leg_top - 1 + bob * 0
    torso_top = torso_bot - th + 1
    head_bot = torso_top  # chin overlaps the collar row
    head_top = head_bot - hh + 1
    if bob:
        head_top += 0
    # Whole upper body bobs down one pixel on steps.
    ub = bob

    x0 = cx - tw // 2
    x1 = x0 + tw - 1

    # ---- tail (behind body) for side/down views drawn first
    if sp["tail"] and facing in ("down", "left"):
        tc = sp["tail"]
        if facing == "left":
            # Tail sweeps out behind (to the right in left-facing view).
            sway = 1 if frame in (1,) else (-1 if frame == 3 else 0)
            pts = [(x1 - 1, torso_bot - 1 + ub), (x1 + 3, torso_bot + 1 + sway), (x1 + 5, torso_bot + 4 + sway),
                   (x1 + 4, torso_bot + 6), (x1 + 2, torso_bot + 3), (x1 - 1, torso_bot + 1 + ub)]
            c.poly(pts, tc)
            c.put(x1 + 4, torso_bot + 5, shade(tc, 0.45))
        else:
            c.poly([(x1 - 1, torso_bot + ub), (x1 + 3, torso_bot + 3), (x1 + 3, torso_bot + 5), (x1, torso_bot + 3)], tc)

    # ---- cloak behind (down view shows edges)
    if sp["cloak"] and facing == "down":
        cl = sp["cloak"]
        c.rect(x0 - 1, torso_top + 1 + ub, x1 + 1, torso_bot + 2, hue_shift_dark(cl, 0.3))

    # ---- legs / robe
    if sp["robe"]:
        rb = sp["robe"]
        rb_d = hue_shift_dark(rb, 0.25)
        for y in range(torso_bot, foot_y + 1):
            k = y - torso_bot
            c.hline(x0 - min(k // 2, 2), x1 + min(k // 2, 2), y, rb)
        c.hline(x0 - 2, x1 + 2, foot_y - 1, rb_d)
        # feet peek out
        if facing != "up":
            c.put(cx - 2 + (step if facing == "down" else 0), foot_y, boots)
            c.put(cx + 1 - (step if facing == "down" else 0), foot_y, boots)
        c.hline(x0 - 2, x1 + 2, foot_y, None)
    else:
        if facing in ("down", "up"):
            lw = max(2, (tw - 2) // 2)
            gap = 1 if tw >= 10 else 0
            for side, s in ((-1, step), (1, -step)):
                lx0 = cx - gap // 2 - lw if side < 0 else cx + (gap + 1) // 2
                lift = 1 if s > 0 else 0
                c.rect(lx0, leg_top, lx0 + lw - 1, foot_y - 2 - lift, pants)
                c.vline(lx0 + (lw - 1 if side < 0 else 0), leg_top, foot_y - 2 - lift, pants_d)
                c.rect(lx0, foot_y - 1 - lift, lx0 + lw - 1, foot_y - lift, boots)
        else:
            # Side view: legs scissor.
            lw = max(2, tw // 2 - 1)
            for k, s in ((0, step), (1, -step)):
                lx = cx - lw // 2 + s * 2
                col = pants if k == 0 else pants_d
                c.rect(lx, leg_top, lx + lw - 1, foot_y - 2, col)
                c.rect(lx - 1 if facing == "left" else lx, foot_y - 1, lx + lw - 1, foot_y, boots)

    # ---- torso
    by0 = torso_top + ub
    by1 = torso_bot + ub
    belly = sp["belly"]
    for y in range(by0, by1 + 1):
        k = y - by0
        bulge = 0
        if belly and k >= th // 3:
            bulge = belly if k < th - 1 else belly - 1
        col = top
        c.hline(x0 - bulge, x1 + bulge, y, col)
    # shading: right side dark, left highlight
    c.vline(x1 + (belly if belly else 0), by0 + 1, by1, top_d)
    c.vline(x0 - (belly if belly else 0), by0 + 1, by1 - 1, top_l)
    if sp["top2"] and facing != "up":
        # Front panel / tunic trim.
        c.vline(cx, by0 + 1, by1, sp["top2"])
        if tw >= 10:
            c.vline(cx - 1, by0 + 1, by1, sp["top2"])
    if sp["belt"] and not sp["robe"]:
        c.hline(x0 - (belly if belly else 0), x1 + (belly if belly else 0), by1, sp["belt"])
        if facing == "down":
            c.put(cx, by1, shade(sp["belt"], 0.5))
    if sp["robe"]:
        c.hline(x0 - belly, x1 + belly, by1 - 1, sp["belt"] or hexc("c08a3a"))

    # pauldrons
    if sp["pauldrons"]:
        pc = sp["pauldrons"]
        c.rect(x0 - 2, by0, x0 + 1, by0 + 1, pc)
        c.rect(x1 - 1, by0, x1 + 2, by0 + 1, pc)
        c.put(x0 - 2, by0 - 1, shade(pc, 0.4))
        c.put(x1 + 2, by0 - 1, shade(pc, 0.4))

    # ---- arms
    arm_c = sp["arm_fur"] or skin
    sleeve = top_d
    aw = sp["arm"]
    attack = frame in (4, 5)
    if facing in ("down", "up"):
        for side in (-1, 1):
            ax = x0 - aw if side < 0 else x1 + 1
            swing = 0
            if frame in (1, 3):
                swing = (1 if frame == 1 else -1) * side
            ay0 = by0 + 1
            ay1 = by1 + (1 if aw > 2 else 0) + swing
            if attack and side > 0 and facing == "down":
                ay1 = by0 + 2 + (0 if frame == 4 else 3)
            c.rect(ax, ay0, ax + aw - 1, ay0 + 1, sleeve)
            c.rect(ax, ay0 + 2, ax + aw - 1, ay1, arm_c)
            hand = sp["arm_fur"] if sp["paws"] else skin
            if sp["paws"]:
                c.rect(ax - (1 if side < 0 else 0), ay1, ax + aw - (0 if side < 0 else -1) - 1 + (1 if side > 0 else 0), ay1 + 1, hand)
            else:
                c.rect(ax, ay1, ax + aw - 1, ay1, skin_l if not sp["arm_fur"] else skin)
            if sp["claws"] and facing == "down":
                c.put(ax + (0 if side < 0 else aw - 1), ay1 + (2 if sp["paws"] else 1), hexc("f0ece0"))
    else:
        # Side view: one arm visible in front, swinging.
        swing = {1: 2, 3: -2}.get(frame, 0)
        ax = cx - aw // 2 - swing // 2
        if attack:
            # Arm thrust forward (to the left).
            reach = 2 if frame == 4 else 5
            c.rect(cx - reach - aw, by0 + 2, cx, by0 + 3, arm_c)
            c.rect(cx - reach - aw - 1, by0 + 2, cx - reach - aw, by0 + 3, skin)
        else:
            c.rect(ax, by0 + 1, ax + aw - 1, by0 + 2, sleeve)
            c.rect(ax, by0 + 3, ax + aw - 1, by1 + 1, arm_c)
            c.put(ax, by1 + 1, skin_l if not sp["arm_fur"] else skin)
            if sp["claws"]:
                c.put(ax - 1, by1 + 1, hexc("f0ece0"))

    # ---- cloak over the back (up / side views)
    if sp["cloak"] and facing in ("up", "left"):
        cl = sp["cloak"]
        cl_d = hue_shift_dark(cl, 0.3)
        if facing == "up":
            c.rect(x0 - 1, by0, x1 + 1, by1 + 2, cl)
            c.vline(x1 + 1, by0 + 1, by1 + 2, cl_d)
            c.hline(x0 - 1, x1 + 1, by1 + 2, cl_d)
        else:
            c.rect(x1 - 1, by0, x1 + 1, by1 + 3, cl)
            c.vline(x1 + 1, by0 + 1, by1 + 3, cl_d)

    # ---- tail over legs in up view
    if sp["tail"] and facing == "up":
        tc = sp["tail"]
        sway = {1: 1, 3: -1}.get(frame, 0)
        c.poly([(cx - 1 + sway, by1 - 1), (cx + 2 + sway, by1 - 1), (cx + 2 + sway * 2, by1 + 5), (cx + sway * 2, by1 + 6), (cx - 1 + sway, by1 + 3)], tc)
        c.put(cx + sway * 2, by1 + 5, shade(tc, 0.45))

    # ---- head
    hx0 = cx - hw // 2
    hx1 = hx0 + hw - 1
    hy0 = head_top + ub
    hy1 = head_bot + ub - 1
    # face shape: rounded rectangle
    for y in range(hy0, hy1 + 1):
        inset = 1 if y in (hy0, hy1) else 0
        c.hline(hx0 + inset, hx1 - inset, y, skin)
    c.vline(hx1, hy0 + 1, hy1 - 1, skin_d)
    if sp["scales"]:
        sc = hue_shift_dark(skin, 0.18)
        for y in range(hy0 + 1, hy1):
            for x in range(hx0 + 1, hx1):
                if (x + y) % 3 == 0 and (y < hy0 + 3 or x < hx0 + 2 or x > hx1 - 2):
                    c.put(x, y, sc)

    eye_y = hy0 + hh // 2 + (1 if hh >= 9 else 0)
    if facing == "down":
        ex = [cx - 3, cx + 2] if hw >= 10 else [cx - 2, cx + 1]
        for e in ex:
            c.put(e, eye_y, sp["eyes"] if not hurt else skin_d)
            c.put(e, eye_y - 1, sp["eyes"] if not hurt and hh >= 9 else (skin_d if hurt else None))
            if sp["iris"] and not hurt and hh >= 9:
                c.put(e, eye_y - 1, sp["iris"])
        if hurt:
            for e in ex:
                c.put(e, eye_y, OUTLINE)
        # blush / mouth
        c.put(cx - 1, eye_y + 2, skin_d)
        c.put(cx, eye_y + 2, skin_d)
        if sp["brow"]:
            c.hline(ex[0] - 1, ex[0] + 1, eye_y - 2, hair_d)
            c.hline(ex[1] - 1, ex[1] + 1, eye_y - 2, hair_d)
        if sp["tusks"]:
            c.put(cx - 2, eye_y + 2, hexc("f4f0e0"))
            c.put(cx + 1, eye_y + 2, hexc("f4f0e0"))
            c.put(cx - 2, eye_y + 1, hexc("f4f0e0"))
            c.put(cx + 1, eye_y + 1, hexc("f4f0e0"))
    elif facing == "left":
        c.put(hx0 + 2, eye_y, sp["eyes"])
        if hh >= 9:
            c.put(hx0 + 2, eye_y - 1, sp["iris"] or sp["eyes"])
        c.put(hx0 - 1, eye_y + 1, skin)  # nose
        c.put(hx0 + 1, eye_y + 2, skin_d)
        if sp["tusks"]:
            c.put(hx0, eye_y + 2, hexc("f4f0e0"))
            c.put(hx0, eye_y + 1, hexc("f4f0e0"))

    # ears (human/pointed)
    if sp["ears"] in (None, "human") and facing in ("down", "left"):
        if facing == "down":
            c.put(hx0 - 1, eye_y, skin_d)
            c.put(hx1 + 1, eye_y, skin_d)
        else:
            c.put(cx + 1, eye_y, skin_d)
    if sp["ears"] == "pointed":
        col = skin
        dk = skin_d

        def ear(x, sx):
            # A solid, swept-back point: 4 px long, tapering.
            for i in range(4):
                c.put(x + sx * i, eye_y - i // 2, col)
                if i < 2:
                    c.put(x + sx * i, eye_y + 1 - i // 2, dk)
            c.put(x + sx * 3, eye_y - 2, col)
        if facing in ("down", "up"):
            ear(hx0 - 1, -1)
            ear(hx1 + 1, 1)
        else:
            ear(cx + 1, 1)

    # ---- hair / hood
    style = sp["hair_style"]
    if sp["hood"]:
        hd = sp["hood"]
        hd_d = hue_shift_dark(hd, 0.3)
        for y in range(hy0 - 1, hy0 + 3 + (hh if facing == "up" else 0)):
            c.hline(hx0 - 1, hx1 + 1, y, hd)
        c.vline(hx0 - 1, hy0, hy1 - (0 if facing == "up" else 2), hd)
        c.vline(hx1 + 1, hy0, hy1 - (0 if facing == "up" else 2), hd_d)
        if facing == "left":
            c.rect(cx, hy0, hx1 + 1, hy1, hd)
        c.put(hx1 + 1, hy0 - 1, hd_d)
        if facing == "up":
            c.rect(hx0 - 1, hy0 - 1, hx1 + 1, hy1, hd)
            c.vline(hx1 + 1, hy0, hy1, hd_d)
    elif style != "none":
        hc, hcd, hcl = hair, hair_d, hair_l
        if facing == "up":
            c.rect(hx0, hy0, hx1, hy1 - (0 if style in ("long", "mane") else 1), hc)
            c.vline(hx1, hy0 + 1, hy1 - 1, hcd)
            if style in ("long", "mane"):
                c.rect(hx0, hy1, hx1, hy1 + 3, hc)
                c.vline(hx1, hy1, hy1 + 3, hcd)
        else:
            # fringe/top
            c.hline(hx0 + 1, hx1 - 1, hy0 - 1, hc)
            c.hline(hx0, hx1, hy0, hc)
            c.hline(hx0, hx1, hy0 + 1, hc)
            if facing == "down":
                c.put(hx0, hy0 + 2, hc)
                c.put(hx1, hy0 + 2, hc)
                c.hline(hx0 + 2, hx0 + 4, hy0 + 2, hc)
                c.put(hx0 + 2, hy0 - 1, hcl)
                c.put(hx0 + 3, hy0 - 1, hcl)
                if style in ("long", "mane"):
                    c.vline(hx0, hy0 + 2, hy1 + 2, hc)
                    c.vline(hx1, hy0 + 2, hy1 + 2, hcd)
                    if style == "mane":
                        c.vline(hx0 - 1, hy0 + 1, hy1 + 1, hc)
                        c.vline(hx1 + 1, hy0 + 1, hy1 + 1, hcd)
            else:
                c.rect(cx - 1, hy0, hx1, hy0 + 3, hc)
                c.rect(cx + 1, hy0 + 3, hx1, hy1 - 1, hc)
                c.vline(hx1, hy0 + 1, hy1 - 1, hcd)
                if style in ("long", "mane"):
                    c.rect(cx + 1, hy1, hx1, hy1 + 3, hc)
        if style == "topknot":
            ty = hy0 - 3
            c.rect(cx - 1, ty, cx + 1, ty + 1, hc)
            c.put(cx - 1, ty + 2, hcd)
            c.put(cx, ty + 2, hc)
        if style == "mohawk":
            for i, x in enumerate(range(cx - 1, cx + 1)):
                pass
            c.rect(cx - 1, hy0 - 3, cx, hy0, hc)
            c.put(cx - 1, hy0 - 4, hcl)

    # ---- animal ears on top
    if sp["ears"] == "wolf":
        ec = sp["arm_fur"] or hair
        inner = hexc("e8a8a0")
        for side in (-1, 1):
            bx = (hx0 + 1) if side < 0 else (hx1 - 3)
            if facing == "left" and side < 0:
                continue
            if facing == "left":
                bx = cx
            c.poly([(bx, hy0 + 1), (bx + 1.5 + (0 if side < 0 else 1), hy0 - 4), (bx + 4, hy0 + 1)], ec)
            if facing != "up":
                c.put(bx + 2, hy0 - 1, inner)
                c.put(bx + 2, hy0, inner)
    if sp["ears"] == "bear":
        ec = sp["arm_fur"] or hair
        inner = hue_shift_dark(ec, 0.35)
        for side in (-1, 1):
            if facing == "left" and side < 0:
                continue
            ex = hx0 + 1 if side < 0 else hx1 - 1
            if facing == "left":
                ex = cx + 1
            c.ellipse(ex + 0.5, hy0, 2.2, 2.0, ec)
            if facing != "up":
                c.put(ex, hy0, inner)

    # ---- fins (Vapouriun)
    if sp["fins"]:
        fc = shade(skin, 0.25)
        fd = hue_shift_dark(skin, 0.1)
        # crest
        c.poly([(cx - 2, hy0 + 1), (cx - 1, hy0 - 4), (cx + 1, hy0 - 3), (cx + 3, hy0 - 1), (cx + 2, hy0 + 1)], fc)
        c.put(cx, hy0 - 2, fd)
        c.put(cx + 1, hy0 - 1, fd)
        if facing in ("down", "up"):
            c.poly([(hx0, eye_y - 2), (hx0 - 3, eye_y - 4), (hx0 - 3, eye_y + 1), (hx0, eye_y + 1)], fc)
            c.poly([(hx1 + 1, eye_y - 2), (hx1 + 4, eye_y - 4), (hx1 + 4, eye_y + 1), (hx1 + 1, eye_y + 1)], fc)
            c.put(hx0 - 2, eye_y - 1, fd)
            c.put(hx1 + 3, eye_y - 1, fd)
        else:
            c.poly([(cx + 1, eye_y - 2), (cx + 5, eye_y - 4), (cx + 5, eye_y + 1), (cx + 1, eye_y + 1)], fc)
            c.put(cx + 4, eye_y - 1, fd)

    # ---- beard
    if sp["beard"] and facing != "up":
        bc = sp["beard"]
        bd = hue_shift_dark(bc, 0.2)
        blen = sp.get("beard_len", 2)
        if facing == "down":
            c.rect(hx0 + 1, eye_y + 1, hx1 - 1, hy1, bc)
            c.put(hx0 + 1, eye_y + 1, skin)
            c.put(hx1 - 1, eye_y + 1, skin)
            c.hline(cx - 1, cx, eye_y + 2, OUTLINE if not sp["tusks"] else bc)
            for i in range(blen):
                c.hline(hx0 + 2 + i, hx1 - 2 - i, hy1 + 1 + i, bc if i < blen - 1 else bd)
        else:
            c.rect(hx0, eye_y + 1, cx + 1, hy1, bc)
            for i in range(blen):
                c.hline(hx0 + i // 2, cx - i // 2, hy1 + 1 + i, bc)

    c.darken_outline(0.5)
    if hurt:
        # White flash tint
        a = c.px[:, :, 3] > 0
        c.px[a, :3] = (c.px[a, :3].astype(int) * 0.5 + 127).astype(np.uint8)
    return c


def char_sheet(sp):
    """Rows: down, left, right, up. Columns: FRAMES."""
    W, H = sp["w"], sp["h"]
    sheet = Canvas(W * len(FRAMES), H * 4)
    for r, facing in enumerate(FACINGS):
        for f in range(len(FRAMES)):
            if facing == "right":
                img = draw_char(sp, "left", f).flipped()
            else:
                img = draw_char(sp, facing, f)
            sheet.paste(img, f * W, r * H)
    return sheet


CHARACTERS = {
    # Player: Emoria Guild warrior (base; tinted variants are generated at runtime via palette swap)
    # Player sheets use key colours (skin #e07070, hair #40b040, cloak #b040b0) that
    # shaders/player_look.gdshader recolours to the chosen appearance.
    "player_short": base_spec(skin=hexc("e07070"), hair=hexc("40b040"), top=hexc("3f5f8f"), top2=hexc("d8b050"),
                              pants=hexc("4a4038"), cloak=hexc("b040b0"), belt=hexc("c89a40")),
    "player_long": base_spec(skin=hexc("e07070"), hair=hexc("40b040"), hair_style="long", top=hexc("3f5f8f"),
                             top2=hexc("d8b050"), pants=hexc("4a4038"), cloak=hexc("b040b0"), belt=hexc("c89a40")),
    "player_topknot": base_spec(skin=hexc("e07070"), hair=hexc("40b040"), hair_style="topknot", top=hexc("3f5f8f"),
                                top2=hexc("d8b050"), pants=hexc("4a4038"), cloak=hexc("b040b0"), belt=hexc("c89a40")),
    "player_none": base_spec(skin=hexc("e07070"), hair=hexc("40b040"), hair_style="none", top=hexc("3f5f8f"),
                             top2=hexc("d8b050"), pants=hexc("4a4038"), cloak=hexc("b040b0"), belt=hexc("c89a40")),
    "human_warden": base_spec(skin=SKIN["light"], hair=HAIR["grey"], top=hexc("6a6a72"), top2=hexc("d8b050"),
                              pants=hexc("3e3a3a"), cloak=hexc("2f4f7f"), beard=HAIR["grey"], brow=True),
    "human_villager": base_spec(skin=SKIN["brown"], hair=HAIR["black"], hair_style="long", top=hexc("a8583e"),
                                pants=hexc("5a4a3a")),
    "human_villager2": base_spec(skin=SKIN["light"], hair=HAIR["blond"], top=hexc("5f8a52"), pants=hexc("5a4a3a")),
    "amir": base_spec(skin=SKIN["tan"], hair=HAIR["wolf"], hair_style="mane", top=hexc("6a4a30"), pants=hexc("4c3c2c"),
                      ears="wolf", tail=hexc("8c8278"), arm_fur=hexc("8c8278"), claws=True, torso_w=9,
                      iris=hexc("d8a020")),
    "burrok": base_spec(w=24, h=32, head_w=12, head_h=10, torso_w=16, torso_h=9, leg_h=7, arm=4,
                        skin=SKIN["brown"], hair=HAIR["bear"], hair_style="mane", top=hexc("6c6c70"),
                        top2=hexc("4a4a50"), pants=hexc("4c3a2a"), ears="bear", beard=HAIR["bear"], beard_len=2,
                        arm_fur=hexc("7a5234"), paws=True, claws=True, brow=True, belt=hexc("6a4a2a")),
    "vapouriun": base_spec(skin=SKIN["vapour"], hair_style="none", top=hexc("3a3030"), top2=hexc("6a5a4a"),
                           pants=hexc("2c3440"), fins=True, scales=True, torso_w=9, iris=hexc("9af0ff"),
                           eyes=hexc("102030")),
    "gouran": base_spec(w=16, h=19, head_w=11, head_h=9, torso_w=9, torso_h=5, leg_h=2, arm=2,
                        skin=SKIN["tan"], hair=HAIR["white"], hood=hexc("6a4a8a"), robe=hexc("6a4a8a"),
                        top=hexc("6a4a8a"), beard=HAIR["white"], beard_len=4, belly=1, brow=True,
                        belt=hexc("c08a3a"), eyes=hexc("303040")),
    "gyria": base_spec(skin=SKIN["gyria"], hair=HAIR["black"], hair_style="topknot", top=hexc("4a3a32"),
                       top2=hexc("7a2a22"), pants=hexc("3a3028"), ears="pointed", tusks=True, torso_w=8, arm=2,
                       belt=hexc("7a2a22"), iris=hexc("e0a020")),
    "gyria_archer": base_spec(skin=SKIN["gyria"], hair=HAIR["black"], hair_style="short", top=hexc("3e4a32"),
                              top2=hexc("6a7a3a"), pants=hexc("3a3028"), ears="pointed", tusks=True, torso_w=8,
                              belt=hexc("5a4a2a"), cloak=hexc("3a4a2a"), iris=hexc("e0a020")),
    "gyria_boss": base_spec(w=24, h=34, head_w=12, head_h=10, torso_w=16, torso_h=10, leg_h=8, arm=4,
                            skin=SKIN["gyria_dark"], hair=HAIR["black"], hair_style="mohawk", top=hexc("3a2a26"),
                            top2=hexc("8a2a20"), pants=hexc("2e2420"), ears="pointed", tusks=True,
                            pauldrons=hexc("8a8a90"), belt=hexc("8a2a20"), brow=True, iris=hexc("ff5020")),
    "gyria_kesh": base_spec(skin=SKIN["gyria"], hair=HAIR["black"], hair_style="long", top=hexc("6a5a48"),
                            pants=hexc("4a4038"), ears="pointed", tusks=True, torso_w=8, belt=None,
                            iris=hexc("e0a020")),
}


# ------------------------------------------------------------------ tiles (16 px)

T = 16
GRASS = hexc("6cb34a")
GRASS_D = hexc("4f9a3c")
GRASS_L = hexc("8ccc5a")
DIRT = hexc("d2b07a")
DIRT_D = hexc("b48e5a")
DIRT_L = hexc("e4c894")
WATER = hexc("4a8fd8")
WATER_D = hexc("3a70c0")
WATER_L = hexc("8ac4f0")
SAND = hexc("e8d8a0")
STONE = hexc("a8a8b0")
STONE_D = hexc("787888")


def tile_grass(var=0):
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, GRASS)
    r = np.random.default_rng(100 + var)
    for _ in range(7 + var * 2):
        x, y = r.integers(0, T), r.integers(1, T)
        c.put(x, y, GRASS_D)
        c.put(x, y - 1, GRASS_D)
        if r.random() < 0.5:
            c.put(x + 1, y - 1, GRASS_L)
    if var == 2:
        for _ in range(3):
            x, y = r.integers(1, T - 1), r.integers(1, T - 1)
            c.put(x, y, GRASS_L)
    return c


def tile_flowers(var=0):
    c = tile_grass(1)
    r = np.random.default_rng(200 + var)
    cols = [hexc("f4f0f0"), hexc("f0d040")] if var == 0 else [hexc("e05a7a"), hexc("f4a0c0")]
    for i in range(3):
        x, y = 2 + i * 5 + r.integers(0, 2), 3 + r.integers(0, 9)
        col = cols[i % 2]
        for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
            c.put(x + dx, y + dy, col)
        c.put(x, y, hexc("f0c030") if var else hexc("e0a020"))
    return c


def tile_tall_grass(frame=0):
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, GRASS_D)
    dark = hexc("3c7a30")
    light = hexc("7cc04e")
    for row in range(3):
        y0 = 4 + row * 5
        for i in range(4):
            x = i * 4 + (2 if row % 2 else 0) + (1 if frame and row == 1 else 0)
            c.poly([(x, y0 + 4), (x + 1, y0 - 2), (x + 2, y0 + 1), (x + 3, y0 - 3), (x + 4, y0 + 4)], light)
            c.put(x + 1, y0 + 1, GRASS)
            c.hline(x, x + 3, y0 + 4, dark)
    return c


def tile_tall_grass_top():
    """Overlay drawn in front of a character's feet when standing in tall grass."""
    c = Canvas(T, T // 2)
    light = hexc("7cc04e")
    dark = hexc("3c7a30")
    for i in range(4):
        x = i * 4
        c.poly([(x, 8), (x + 1, 1), (x + 2, 4), (x + 3, 0), (x + 4, 8)], light)
        c.put(x + 2, 6, GRASS)
        c.hline(x, x + 3, 7, dark)
    return c


def edge_tile(base_fn, edge_col, mask, outer_fn, rim=None):
    """mask bits: 1 = N, 2 = E, 4 = S, 8 = W neighbour is the SAME terrain.
    Draws terrain with rounded borders where neighbours differ."""
    c = outer_fn()
    b = base_fn()
    n, e, s, w = bool(mask & 1), bool(mask & 2), bool(mask & 4), bool(mask & 8)
    for y in range(T):
        for x in range(T):
            inside = True
            d = 99
            if not n:
                d = min(d, y)
            if not s:
                d = min(d, T - 1 - y)
            if not w:
                d = min(d, x)
            if not e:
                d = min(d, T - 1 - x)
            # Rounded corners
            corner = 0
            if not n and not w:
                corner = max(corner, 3 - math.hypot(x - 3, y - 3) if x < 3 and y < 3 else 0)
                if x < 3 and y < 3 and math.hypot(x - 2.5, y - 2.5) > 2.6:
                    inside = False
            if not n and not e:
                if x > T - 4 and y < 3 and math.hypot(x - (T - 3.5), y - 2.5) > 2.6:
                    inside = False
            if not s and not w:
                if x < 3 and y > T - 4 and math.hypot(x - 2.5, y - (T - 3.5)) > 2.6:
                    inside = False
            if not s and not e:
                if x > T - 4 and y > T - 4 and math.hypot(x - (T - 3.5), y - (T - 3.5)) > 2.6:
                    inside = False
            if d < 1:
                inside = False
            if inside:
                col = tuple(b.px[y, x])
                if rim and d < 2:
                    col = rim
                c.px[y, x] = col
            elif d < 2 and edge_col is not None and (d >= 0):
                pass
    return c


def tile_dirt_base():
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, DIRT)
    r = np.random.default_rng(300)
    for _ in range(10):
        x, y = r.integers(0, T), r.integers(0, T)
        c.put(x, y, DIRT_D if r.random() < 0.6 else DIRT_L)
    return c


def tile_water_base(frame=0):
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, WATER)
    for i in range(3):
        y = 3 + i * 5
        x = (i * 5 + frame * 3) % T
        c.hline(x, x + 3, y, WATER_L)
        c.hline((x + 8) % T, (x + 9) % T, y + 2, WATER_D)
    return c


def tile_sand():
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, SAND)
    r = np.random.default_rng(400)
    for _ in range(8):
        c.put(r.integers(0, T), r.integers(0, T), hexc("d4c088"))
    return c


def tile_stone_floor():
    c = Canvas(T, T)
    c.rect(0, 0, T - 1, T - 1, STONE)
    c.hline(0, T - 1, 7, STONE_D)
    c.hline(0, T - 1, 15, STONE_D)
    c.vline(5, 0, 7, STONE_D)
    c.vline(12, 8, 15, STONE_D)
    c.hline(0, 4, 0, shade(STONE, 0.3))
    c.hline(6, T - 1, 8, shade(STONE, 0.3))
    return c


def tile_planks():
    c = Canvas(T, T)
    wood = hexc("b07a48")
    c.rect(0, 0, T - 1, T - 1, wood)
    for y in (4, 9, 14):
        c.hline(0, T - 1, y, hexc("8a5a34"))
    c.put(3, 2, hexc("8a5a34"))
    c.put(11, 7, hexc("8a5a34"))
    return c


def tile_cliff(top=True):
    """Rock face: used as an impassable wall; 'top' has grass lip."""
    c = Canvas(T, T)
    rock = hexc("9a8a78")
    rd = hexc("6e6052")
    rl = hexc("c0b098")
    c.rect(0, 0, T - 1, T - 1, rock)
    for y in range(0, T, 5):
        c.hline(0, T - 1, y + 4, rd)
    for x in (3, 9, 13):
        c.vline(x, 0, T - 1, rd)
    c.put(5, 2, rl)
    c.put(11, 8, rl)
    if top:
        c.rect(0, 0, T - 1, 3, GRASS)
        c.hline(0, T - 1, 3, GRASS_D)
        c.hline(0, T - 1, 4, OUTLINE)
    return c


def tile_fence(kind="h"):
    c = Canvas(T, T)
    wood = hexc("c08a54")
    wd = hexc("7a5030")
    if kind == "h":
        c.rect(0, 6, T - 1, 7, wood)
        c.rect(0, 10, T - 1, 11, wood)
        c.hline(0, T - 1, 8, wd)
        c.hline(0, T - 1, 12, wd)
        for x in (1, 13):
            c.rect(x, 3, x + 1, 14, wood)
            c.vline(x + 1, 4, 14, wd)
    else:
        c.rect(7, 0, 8, T - 1, wood)
        c.vline(8, 0, T - 1, wd)
    c.darken_outline(0.5)
    return c


def obj_tree(kind="round"):
    c = Canvas(32, 40)
    trunk = hexc("8a5a34")
    trunk_d = hexc("5e3c22")
    c.rect(13, 26, 18, 37, trunk)
    c.vline(18, 26, 37, trunk_d)
    c.hline(11, 20, 37, trunk_d)
    c.put(12, 37, trunk)
    c.put(19, 37, trunk)
    if kind == "round":
        leaf = hexc("4f9a3c")
        leaf_d = hexc("357a30")
        leaf_l = hexc("7cc04e")
        leaf_h = hexc("a8dc6a")
        blobs = [(16, 13, 13, 11), (9, 18, 7, 7), (23, 18, 7, 7), (16, 22, 10, 6), (11, 9, 6, 6), (21, 9, 6, 6)]
        for bx, by, rx, ry in blobs:
            c.ellipse(bx, by + 1, rx, ry, leaf_d)
        for bx, by, rx, ry in blobs:
            c.ellipse(bx - 0.5, by - 0.5, rx - 1, ry - 1, leaf)
        for bx, by, rx, ry in blobs[:1] + blobs[4:]:
            c.ellipse(bx - 2, by - 2, rx * 0.45, ry * 0.4, leaf_l)
        r = np.random.default_rng(5)
        for _ in range(12):
            x, y = r.integers(6, 26), r.integers(4, 24)
            if c.px[y, x, 3] and tuple(c.px[y, x]) == leaf_l:
                c.put(x, y, leaf_h)
        for _ in range(16):
            x, y = r.integers(4, 28), r.integers(8, 27)
            if c.px[y, x, 3] and tuple(c.px[y, x]) == leaf:
                c.put(x, y, leaf_d)
    else:
        leaf = hexc("2f7a4a")
        leaf_d = hexc("1f5a3a")
        leaf_l = hexc("4f9a5a")
        for i, (w, y) in enumerate([(5, 4), (8, 10), (11, 16), (14, 22)]):
            c.poly([(16 - w, y + 8), (16, y - 4), (16 + w, y + 8)], leaf_d)
            c.poly([(16 - w + 1, y + 6), (16, y - 3), (16 + w - 2, y + 6)], leaf)
            c.line(16, y - 2, 16 - w + 3, y + 5, leaf_l)
        c.rect(14, 28, 17, 37, trunk)
    c.darken_outline(0.55)
    return c


def obj_bush(cut=False):
    c = Canvas(T, T)
    if cut:
        c.ellipse(8, 12, 5, 2.5, hexc("4f9a3c"))
        c.hline(4, 11, 12, hexc("357a30"))
    else:
        c.ellipse(8, 9, 7, 6, hexc("357a30"))
        c.ellipse(7.5, 8, 6, 5, hexc("5aaa40"))
        c.ellipse(6, 6, 3, 2, hexc("8ccc5a"))
        c.put(10, 10, hexc("357a30"))
        c.put(4, 9, hexc("357a30"))
    c.darken_outline(0.55)
    return c


def obj_rock():
    c = Canvas(T, T)
    c.ellipse(8, 10, 7, 5, STONE_D)
    c.ellipse(7.5, 9, 6, 4, STONE)
    c.ellipse(6, 7.5, 3, 1.6, hexc("d0d0d8"))
    c.darken_outline(0.55)
    return c


def obj_sign():
    c = Canvas(T, T)
    wood = hexc("c08a54")
    c.rect(2, 3, 13, 10, wood)
    c.hline(4, 11, 5, hexc("7a5030"))
    c.hline(4, 9, 7, hexc("7a5030"))
    c.rect(7, 11, 8, 15, hexc("8a5a34"))
    c.darken_outline(0.5)
    return c


def obj_chest(opened=False):
    c = Canvas(T, T)
    wood = hexc("a86a30")
    wd = hexc("6e4420")
    gold = hexc("f0c040")
    c.rect(2, 6, 13, 14, wood)
    c.hline(2, 13, 9, wd)
    c.vline(2, 6, 14, wd)
    c.vline(13, 6, 14, wd)
    c.rect(7, 8, 8, 10, gold)
    if opened:
        c.rect(2, 2, 13, 5, wd)
        c.rect(3, 6, 12, 8, hexc("2a1a14"))
    else:
        c.rect(2, 3, 13, 6, wood)
        c.hline(3, 12, 3, shade(wood, 0.3))
    c.darken_outline(0.5)
    return c


def obj_ring_stone(glow=0):
    c = Canvas(T, 32)
    st = hexc("8a8aa0")
    sd = hexc("5a5a78")
    c.poly([(3, 30), (4, 8), (8, 3), (12, 8), (13, 30)], st)
    c.vline(12, 9, 30, sd)
    c.hline(3, 13, 30, sd)
    g = [hexc("7ae0ff"), hexc("b0f4ff")][glow % 2]
    c.ellipse(8, 14, 3, 3, g)
    c.ellipse(8, 14, 1.5, 1.5, hexc("ffffff"))
    c.vline(8, 19, 26, g)
    c.darken_outline(0.5)
    return c


def obj_house(roof=hexc("b04a3a"), wall=hexc("e8d8b8"), w=64, h=56):
    c = Canvas(w, h)
    rd = hue_shift_dark(roof, 0.3)
    rl = shade(roof, 0.2)
    wd = hue_shift_dark(wall, 0.2)
    wall_top = 26
    c.rect(4, wall_top, w - 5, h - 1, wall)
    c.vline(w - 5, wall_top, h - 1, wd)
    for y in range(wall_top + 4, h, 6):
        c.hline(4, w - 5, y, shade(wall, -0.06))
    # roof: trapezoid with shingles
    c.poly([(0, wall_top + 2), (10, 2), (w - 10, 2), (w, wall_top + 2)], roof)
    for y in range(6, wall_top + 2, 4):
        c.line(int(10 - (y - 2) * 10 / 24), y, int(w - 10 + (y - 2) * 10 / 24), y, rd)
    c.line(10, 2, w - 10, 2, rl)
    c.rect(0, wall_top + 2, w, wall_top + 3, rd)
    # door
    dx = w // 2 - 5
    c.rect(dx, h - 15, dx + 9, h - 1, hexc("7a4a2a"))
    c.rect(dx + 1, h - 14, dx + 8, h - 1, hexc("9a6038"))
    c.put(dx + 7, h - 8, hexc("f0c040"))
    # windows
    for wx in (10, w - 20):
        c.rect(wx, wall_top + 8, wx + 9, wall_top + 16, hexc("5a4030"))
        c.rect(wx + 1, wall_top + 9, wx + 8, wall_top + 15, hexc("9ad0f0"))
        c.vline(wx + 4, wall_top + 9, wall_top + 15, hexc("5a4030"))
        c.put(wx + 2, wall_top + 10, hexc("e0f4ff"))
    c.darken_outline(0.55)
    return c


def obj_guild_hall():
    c = obj_house(roof=hexc("3a5a9a"), wall=hexc("d8d0c0"), w=96, h=72)
    # banner with the Guild ring
    for bx in (20, 70):
        c.rect(bx, 38, bx + 6, 52, hexc("2f4f7f"))
        c.ellipse(bx + 3.5, 44, 2.4, 2.4, hexc("f0c040"))
        c.ellipse(bx + 3.5, 44, 1.0, 1.0, hexc("2f4f7f"))
    return c


def obj_tent(col=hexc("8a6a48")):
    c = Canvas(40, 32)
    d = hue_shift_dark(col, 0.3)
    c.poly([(1, 31), (20, 2), (39, 31)], col)
    c.poly([(20, 2), (39, 31), (24, 31)], d)
    c.poly([(16, 31), (20, 16), (24, 31)], hexc("2a1e18"))
    c.line(20, 0, 20, 3, hexc("5a3a20"))
    c.darken_outline(0.55)
    return c


def obj_campfire(frame=0):
    c = Canvas(T, T)
    c.rect(3, 12, 12, 13, hexc("6e4420"))
    c.line(3, 14, 12, 11, hexc("8a5a34"))
    fl = [hexc("f04020"), hexc("f8a020"), hexc("fff080")]
    h = 8 + frame
    c.poly([(4, 12), (8, 12 - h), (12, 12)], fl[0])
    c.poly([(6, 12), (8 + (frame - 0.5), 12 - h + 3), (10, 12)], fl[1])
    c.poly([(7, 12), (8, 8), (9, 12)], fl[2])
    return c


def obj_lore_stone():
    c = Canvas(T, 24)
    c.poly([(2, 23), (3, 4), (8, 1), (13, 4), (14, 23)], hexc("7a8a7a"))
    for y in (7, 10, 13, 16):
        c.hline(5, 11, y, hexc("a0f0c0"))
    c.darken_outline(0.5)
    return c


# ------------------------------------------------------------------ creatures (labelled test creatures)

def creature_canvas(size):
    return Canvas(size, size)


def draw_creature(kind, view="front", size=48, frame=0):
    """Test creatures, deliberately simple and labelled as placeholders."""
    c = creature_canvas(size)
    s = size / 48.0
    bob = frame % 2

    def E(cx, cy, rx, ry, col):
        c.ellipse(cx * s, (cy + bob) * s, rx * s, ry * s, col)

    def P(pts, col):
        c.poly([(x * s, (y + bob) * s) for x, y in pts], col)

    if kind == "alpha":  # Ember: small fox-like quadruped
        body, dark, light = hexc("e07a3a"), hexc("a84a2a"), hexc("f8c890")
        P([(8, 18), (11, 4), (17, 15)], body)  # ear
        P([(24, 15), (31, 4), (32, 18)], body)
        E(30, 34, 12, 9, body)  # body
        E(20, 22, 11, 10, body)  # head
        E(20, 27, 6, 4, light)
        for x in (22, 34):
            c.rect(x * s, (40 + bob) * s, (x + 3) * s, 45 * s, dark)
        P([(40, 30), (47, 18), (45, 34)], hexc("f8a040"))  # flame tail
        P([(42, 28), (46, 22), (45, 31)], hexc("fff080"))
        if view == "front":
            c.rect(15 * s, (20 + bob) * s, 16 * s, (22 + bob) * s, OUTLINE)
            c.rect(23 * s, (20 + bob) * s, 24 * s, (22 + bob) * s, OUTLINE)
            c.put(19.5 * s, (26 + bob) * s, OUTLINE)
    elif kind == "beta":  # Tide: round amphibian
        body, light = hexc("4aa0d8"), hexc("a8e0f8")
        E(24, 30, 17, 14, body)
        E(24, 34, 11, 8, light)
        E(14, 16, 5, 5, body)
        E(34, 16, 5, 5, body)
        P([(22, 14), (26, 6), (30, 14)], hexc("6ac0f0"))
        if view == "front":
            E(14, 16, 2.5, 2.5, hexc("ffffff"))
            E(34, 16, 2.5, 2.5, hexc("ffffff"))
            c.rect(13.5 * s, (15 + bob) * s, 15 * s, (17 + bob) * s, OUTLINE)
            c.rect(33.5 * s, (15 + bob) * s, 35 * s, (17 + bob) * s, OUTLINE)
            c.line(18 * s, (27 + bob) * s, 30 * s, (27 + bob) * s, OUTLINE)
        for x in (12, 32):
            E(x + 2, 43, 5, 3, hexc("3a80b8"))
    elif kind == "gamma":  # Verdant: leafy beetle
        shell, dark, leaf = hexc("6a9a3a"), hexc("3e6a2a"), hexc("9ad05a")
        E(24, 30, 16, 12, shell)
        c.line(24 * s, (19 + bob) * s, 24 * s, (42 + bob) * s, dark)
        E(24, 17, 8, 6, hexc("5a4a3a"))
        P([(20, 12), (14, 2), (22, 9)], leaf)
        P([(28, 12), (34, 2), (26, 9)], leaf)
        for i in range(3):
            c.line((10 + i * 3) * s, (32 + i * 4 + bob) * s, (4 + i * 2) * s, (36 + i * 4) * s, dark)
            c.line((38 - i * 3) * s, (32 + i * 4 + bob) * s, (44 - i * 2) * s, (36 + i * 4) * s, dark)
        if view == "front":
            c.rect(20 * s, (16 + bob) * s, 21 * s, (17 + bob) * s, hexc("f0f060"))
            c.rect(27 * s, (16 + bob) * s, 28 * s, (17 + bob) * s, hexc("f0f060"))
        E(18, 26, 4, 3, leaf)
    elif kind == "delta":  # Gale: small bird
        body, wing, light = hexc("b8b0e0"), hexc("8a80c0"), hexc("f0f0ff")
        E(24, 28, 12, 11, body)
        E(24, 31, 7, 6, light)
        P([(12, 26), (2, 18 - bob * 3), (8, 32)], wing)
        P([(36, 26), (46, 18 - bob * 3), (40, 32)], wing)
        P([(22, 27), (24, 31), (26, 27)], hexc("f0b030"))
        P([(20, 16), (24, 8), (27, 17)], wing)
        if view == "front":
            c.rect(19 * s, (23 + bob) * s, 20 * s, (24 + bob) * s, OUTLINE)
            c.rect(28 * s, (23 + bob) * s, 29 * s, (24 + bob) * s, OUTLINE)
        c.line(20 * s, 39 * s, 20 * s, 44 * s, hexc("f0b030"))
        c.line(28 * s, 39 * s, 28 * s, 44 * s, hexc("f0b030"))
    elif kind == "epsilon":  # Stone: rocky armadillo
        body, dark, light = hexc("9a8a7a"), hexc("6a5a4e"), hexc("c8b8a4")
        E(24, 30, 18, 12, body)
        for i in range(4):
            c.line((12 + i * 8) * s, (20 + bob) * s, (12 + i * 8) * s, (40 + bob) * s, dark)
        E(8, 32, 6, 5, light)
        if view == "front":
            c.rect(6 * s, (30 + bob) * s, 7 * s, (31 + bob) * s, OUTLINE)
        for x in (12, 32):
            c.rect(x * s, (40 + bob) * s, (x + 4) * s, 45 * s, dark)
    if view == "back":
        # Back view: slightly darker overall.
        a = c.px[:, :, 3] > 0
        c.px[a, :3] = (c.px[a, :3].astype(int) * 0.85).astype(np.uint8)
    c.darken_outline(0.5)
    return c


CREATURES = ["alpha", "beta", "gamma", "delta", "epsilon"]


# ------------------------------------------------------------------ effects / UI

def fx_slash(direction):
    """24x24 sword arc for a direction."""
    c = Canvas(24, 24)
    for i in range(14):
        t = i / 13
        ang = -1.2 + 2.4 * t
        r0, r1 = 7, 11
        for r in np.arange(r0, r1, 0.5):
            x = 12 + math.cos(ang) * r
            y = 12 + math.sin(ang) * r
            col = hexc("ffffff") if r > 9.5 else hexc("b8e0ff")
            c.put(x, y, (*col[:3], int(255 * (0.4 + 0.6 * t))))
    rot = {"right": 0, "down": 1, "left": 2, "up": 3}[direction]
    c.px = np.rot90(c.px, -rot).copy()
    return c


def fx_spark(frame):
    c = Canvas(16, 16)
    r = 2 + frame * 2
    col = [hexc("ffffff"), hexc("fff080"), hexc("f8a020")][min(frame, 2)]
    for k in range(8):
        a = k * math.pi / 4
        c.line(8, 8, 8 + math.cos(a) * r, 8 + math.sin(a) * r, col)
    return c


def ui_heart(fill):
    c = Canvas(9, 8)
    red = hexc("e83a3a")
    empty = hexc("5a3a46")
    pts = [(0.5, 2), (2, 0.5), (4.5, 2), (7, 0.5), (8.5, 2), (8.5, 3.5), (4.5, 7.8), (0.5, 3.5)]
    c.poly(pts, empty)
    if fill >= 1:
        c.poly(pts, red)
    elif fill > 0:
        c.poly([(0.5, 2), (2, 0.5), (4.5, 2), (4.5, 7.8), (0.5, 3.5)], red)
    c.put(2, 2, hexc("ffb0b0") if fill > 0 else empty)
    c.outline(OUTLINE)
    return c


def ui_ring():
    c = Canvas(12, 12)
    c.ellipse(6, 6, 5, 5, hexc("f0c040"))
    c.ellipse(6, 6, 3, 3, (0, 0, 0, 0))
    c.px[np.all(c.px == 0, axis=2)] = 0
    c.put(6, 1, hexc("7ae0ff"))
    c.put(5, 1, hexc("b0f4ff"))
    c.outline(OUTLINE)
    return c


def ui_coin():
    c = Canvas(8, 8)
    c.ellipse(4, 4, 3.5, 3.5, hexc("f0c040"))
    c.ellipse(3.5, 3.5, 1.5, 2, hexc("fff0a0"))
    c.outline(OUTLINE)
    return c


def obj_heart_pickup():
    c = Canvas(T, T)
    c.paste(ui_heart(1), 3, 4)
    return c


def obj_arrow():
    c = Canvas(T, 4)
    c.hline(1, 12, 1, hexc("8a5a34"))
    c.hline(1, 12, 2, hexc("6e4420"))
    c.poly([(12, 0), (15, 1.5), (12, 3.5)], hexc("c8c8d0"))
    c.rect(0, 0, 2, 3, hexc("e0e0e0"))
    return c


def obj_weapon(kind):
    """Small held weapons for overworld sprites (drawn pointing right)."""
    c = Canvas(16, 16)
    steel = hexc("d0d8e0")
    sd = hexc("8a92a0")
    if kind == "sword":
        c.rect(2, 7, 12, 8, steel)
        c.hline(2, 12, 8, sd)
        c.poly([(12, 7), (15, 7.5), (12, 9)], steel)
        c.rect(0, 6, 1, 9, hexc("f0c040"))
        c.rect(-2, 7, 0, 8, hexc("6e4420"))
    elif kind == "spear":
        c.hline(0, 12, 8, hexc("8a5a34"))
        c.poly([(12, 6), (16, 8), (12, 10)], steel)
    elif kind == "staff":
        c.hline(0, 12, 8, hexc("8a5a34"))
        c.ellipse(13.5, 8, 2.2, 2.2, hexc("7ae0ff"))
    elif kind == "dagger":
        c.rect(5, 7, 10, 8, steel)
        c.rect(3, 6, 4, 9, hexc("6e4420"))
    elif kind == "axe":
        c.hline(0, 12, 8, hexc("8a5a34"))
        c.poly([(9, 3), (14, 4), (15, 8), (14, 12), (9, 13)], steel)
    elif kind == "hookblade":
        c.rect(2, 7, 11, 8, steel)
        c.poly([(11, 7), (14, 4), (13, 8)], steel)
        c.rect(0, 6, 2, 9, hexc("5a3a20"))
    elif kind == "bow":
        for i in range(-6, 7):
            c.put(6 + (36 - i * i) ** 0.5 * 0.6, 8 + i, hexc("8a5a34"))
        c.vline(6, 2, 14, hexc("e0e0e0"))
    c.darken_outline(0.5)
    return c


# ------------------------------------------------------------------ atlas assembly

TILE_INDEX = {}


def build_tiles():
    """Tile atlas: 16 columns x N rows of 16 px tiles. Returns name -> (col,row)."""
    tiles = []

    def add(name, canvas):
        TILE_INDEX[name] = len(tiles)
        tiles.append(canvas)
    for i in range(3):
        add("grass%d" % i, tile_grass(i))
    add("flowers0", tile_flowers(0))
    add("flowers1", tile_flowers(1))
    add("tallgrass", tile_tall_grass(0))
    add("tallgrass_b", tile_tall_grass(1))
    add("sand", tile_sand())
    add("stone", tile_stone_floor())
    add("planks", tile_planks())
    add("cliff", tile_cliff(True))
    add("cliff_face", tile_cliff(False))
    add("fence_h", tile_fence("h"))
    add("fence_v", tile_fence("v"))
    # Path and water edges: 16 masks each, on grass.
    for m in range(16):
        add("path%d" % m, edge_tile(tile_dirt_base, None, m, lambda: tile_grass(0), rim=DIRT_D))
    for f in range(2):
        for m in range(16):
            add("water%d_%d" % (f, m), edge_tile(lambda: tile_water_base(f), None, m, tile_sand, rim=WATER_L))
    cols = 16
    rows = (len(tiles) + cols - 1) // cols
    atlas = Canvas(cols * T, rows * T)
    for i, t in enumerate(tiles):
        atlas.paste(t, (i % cols) * T, (i // cols) * T)
    return atlas


def save(canvas, rel):
    path = os.path.join(ART, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    canvas.image().save(path)


def main():
    preview = "--preview" in sys.argv
    atlas = build_tiles()
    save(atlas, "tiles.png")
    with open(os.path.join(ART, "tiles.json"), "w") as f:
        import json
        json.dump({"tile_size": T, "columns": 16, "tiles": TILE_INDEX}, f, indent=1)
    for name, sp in CHARACTERS.items():
        sheet = char_sheet(sp)
        save(sheet, "chars/%s.png" % name)
    objs = {
        "tree": obj_tree("round"), "pine": obj_tree("pine"), "bush": obj_bush(False), "bush_cut": obj_bush(True),
        "rock": obj_rock(), "sign": obj_sign(), "chest": obj_chest(False), "chest_open": obj_chest(True),
        "ring_stone0": obj_ring_stone(0), "ring_stone1": obj_ring_stone(1), "house_red": obj_house(),
        "house_green": obj_house(roof=hexc("4a8a4a"), wall=hexc("e0d0b0")), "guild_hall": obj_guild_hall(),
        "tent": obj_tent(), "tent_red": obj_tent(hexc("8a3a2a")), "campfire0": obj_campfire(0), "campfire1": obj_campfire(1),
        "lore_stone": obj_lore_stone(), "heart": obj_heart_pickup(), "arrow": obj_arrow(),
        "grass_top": tile_tall_grass_top(),
    }
    for name, cv in objs.items():
        save(cv, "objects/%s.png" % name)
    for w in ["sword", "spear", "staff", "dagger", "axe", "hookblade", "bow"]:
        save(obj_weapon(w), "weapons/%s.png" % w)
    for kind in CREATURES:
        save(draw_creature(kind, "front", 48), "creatures/%s_front.png" % kind)
        save(draw_creature(kind, "back", 48), "creatures/%s_back.png" % kind)
        ow = Canvas(32, 16)
        ow.paste(draw_creature(kind, "front", 16, 0), 0, 0)
        ow.paste(draw_creature(kind, "front", 16, 1), 16, 0)
        save(ow, "creatures/%s_small.png" % kind)
    for d in ["down", "up", "left", "right"]:
        save(fx_slash(d), "fx/slash_%s.png" % d)
    sp = Canvas(48, 16)
    for i in range(3):
        sp.paste(fx_spark(i), i * 16, 0)
    save(sp, "fx/spark.png")
    hearts = Canvas(27, 8)
    for i, fill in enumerate([1, 0.5, 0]):
        hearts.paste(ui_heart(fill), i * 9, 0)
    save(hearts, "ui/hearts.png")
    save(ui_ring(), "ui/ring.png")
    save(ui_coin(), "ui/coin.png")
    if preview:
        make_previews()
    print("art written to", os.path.relpath(ART, ROOT))


def make_previews():
    out = os.path.join(HERE, "art_preview")
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, ".gdignore"), "w").close()
    # Character line-up: every character, down/left/up idle + step frames, x6.
    names = list(CHARACTERS)
    cell_w, cell_h = 28, 36
    sheet = Canvas(cell_w * 6, cell_h * len(names))
    for r, n in enumerate(names):
        sp = CHARACTERS[n]
        for k, (facing, f) in enumerate([("down", 0), ("down", 1), ("left", 0), ("left", 3), ("up", 0), ("down", 5)]):
            img = draw_char(sp, facing, f)
            sheet.paste(img, k * cell_w + (cell_w - sp["w"]) // 2, r * cell_h + (cell_h - sp["h"]))
    bg = Image.new("RGBA", (sheet.w, sheet.h), (110, 170, 80, 255))
    bg.alpha_composite(sheet.image())
    bg.resize((sheet.w * 5, sheet.h * 5), Image.NEAREST).save(os.path.join(out, "characters.png"))


if __name__ == "__main__":
    main()
