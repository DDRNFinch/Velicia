#!/usr/bin/env python3
"""Builds Velicia's realistic character models from the CC0 MakeHuman base mesh.

For every people (and body variant) this script:
  1. downloads the MakeHuman base mesh, default skeleton, weights and the
     morph targets it needs (all CC0, cached in tools/mh_cache/),
  2. shapes the body with morph targets (muscle, weight, proportions, age,
     ears, nose, belly, leg length ...),
  3. re-poses it from MakeHuman's A-pose to the game's rest pose (arms down,
     legs together, hands in a grip),
  4. paints clothing regions (shirt, sleeves, trousers, boots, belt, robe,
     fur) onto the skin with a small inflation so cloth sits over the body,
  5. adds the people's features: eyes, hair caps, beards, hoods, cloaks,
     wolf/bear ears, claws, bear paws, fins, tusks and a tail,
  6. simplifies the 163-bone MakeHuman rig to a 20-bone game rig whose bones
     match the animation pivots in PlaceholderBody, and
  7. writes a skinned binary glTF to models/characters/<name>.glb.

Material names in the GLB (skin, top, pants, boots, belt, robe, fur, hair,
beard, eyes, claw, fin, cloak, hood) are replaced at runtime by
CharacterModel, which tints them per character.

Usage:  python3 tools/build_characters.py [name ...]     (needs numpy)
"""
import json
import math
import os
import struct
import subprocess
import sys
import urllib.request

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
CACHE = os.path.join(HERE, "mh_cache")
OUT = os.path.join(ROOT, "models", "characters")
MH = "https://raw.githubusercontent.com/makehumancommunity/makehuman/master/makehuman/data/"


# ----------------------------------------------------------------- assets

def fetch(rel):
    os.makedirs(CACHE, exist_ok=True)
    gd = os.path.join(CACHE, ".gdignore")
    if not os.path.exists(gd):
        open(gd, "w").close()
    path = os.path.join(CACHE, rel.replace("/", "__"))
    if not os.path.exists(path):
        url = MH + rel
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                data = r.read()
        except Exception:
            data = subprocess.run(["curl", "-sfL", "-m", "120", url], check=True, capture_output=True).stdout
        with open(path, "wb") as f:
            f.write(data)
    return path


def load_obj():
    v, vt, groups, cur = [], [], {}, None
    for line in open(fetch("3dobjs/base.obj")):
        if line.startswith("v "):
            v.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("vt "):
            vt.append([float(x) for x in line.split()[1:3]])
        elif line.startswith("g "):
            cur = line.split()[1]
            groups.setdefault(cur, [])
        elif line.startswith("f "):
            face = []
            for t in line.split()[1:]:
                parts = t.split("/")
                face.append((int(parts[0]) - 1, int(parts[1]) - 1 if len(parts) > 1 and parts[1] else 0))
            groups[cur].append(face)
    return np.array(v), np.array(vt), groups


_target_cache = {}


def load_target(name):
    if name not in _target_cache:
        idx, d = [], []
        for line in open(fetch("targets/" + name + ".target")):
            if line.startswith("#") or not line.strip():
                continue
            p = line.split()
            idx.append(int(p[0]))
            d.append([float(p[1]), float(p[2]), float(p[3])])
        _target_cache[name] = (np.array(idx, dtype=int), np.array(d))
    return _target_cache[name]


# ----------------------------------------------------------------- maths

def normalize(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-9)


def rot_between(a, b):
    a, b = normalize(np.asarray(a, float)), normalize(np.asarray(b, float))
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if np.linalg.norm(v) < 1e-8:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k * (1.0 / (1.0 + c))


def axis_angle(axis, ang):
    x, y, z = normalize(np.asarray(axis, float))
    c, s, t = math.cos(ang), math.sin(ang), 1 - math.cos(ang)
    return np.array([[t * x * x + c, t * x * y - s * z, t * x * z + s * y],
                     [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
                     [t * x * z - s * y, t * y * z + s * x, t * z * z + c]])


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------- rig

SIDES = ("L", "R")
GAME_BONES = [("Hips", None, "root"), ("Spine", "Hips", "spine04"), ("Chest", "Spine", "spine02"),
              ("Neck", "Chest", "neck01"), ("Head", "Neck", "head")]
for _s in SIDES:
    GAME_BONES += [
        ("Clavicle_" + _s, "Chest", "clavicle." + _s), ("UpperArm_" + _s, "Clavicle_" + _s, "upperarm01." + _s),
        ("LowerArm_" + _s, "UpperArm_" + _s, "lowerarm01." + _s), ("Hand_" + _s, "LowerArm_" + _s, "wrist." + _s),
        ("UpperLeg_" + _s, "Hips", "upperleg01." + _s), ("LowerLeg_" + _s, "UpperLeg_" + _s, "lowerleg01." + _s),
        ("Foot_" + _s, "LowerLeg_" + _s, "foot." + _s),
    ]
ANCHORS = {"root": "Hips", "spine05": "Hips", "spine04": "Spine", "spine03": "Spine", "spine02": "Chest",
           "spine01": "Chest", "neck01": "Neck", "neck02": "Neck", "neck03": "Neck", "head": "Head"}
for _s in SIDES:
    ANCHORS.update({"pelvis." + _s: "Hips", "clavicle." + _s: "Clavicle_" + _s, "shoulder01." + _s: "Clavicle_" + _s,
                    "upperarm01." + _s: "UpperArm_" + _s, "upperarm02." + _s: "UpperArm_" + _s,
                    "lowerarm01." + _s: "LowerArm_" + _s, "lowerarm02." + _s: "LowerArm_" + _s,
                    "wrist." + _s: "Hand_" + _s, "upperleg01." + _s: "UpperLeg_" + _s,
                    "upperleg02." + _s: "UpperLeg_" + _s, "lowerleg01." + _s: "LowerLeg_" + _s,
                    "lowerleg02." + _s: "LowerLeg_" + _s, "foot." + _s: "Foot_" + _s})
TAIL_BONES = 5


class Rig:
    def __init__(self):
        sk = json.load(open(fetch("rigs/default.mhskel")))
        self.bones = sk["bones"]
        self.joint_verts = sk["joints"]
        self.weights = json.load(open(fetch("rigs/default_weights.mhw")))["weights"]
        order, seen = [], set()

        def visit(b):
            if b in seen:
                return
            p = self.bones[b]["parent"]
            if p:
                visit(p)
            seen.add(b)
            order.append(b)
        for b in self.bones:
            visit(b)
        self.order = order

    def anchor(self, b):
        while b not in ANCHORS:
            b = self.bones[b]["parent"]
        return ANCHORS[b]


# ----------------------------------------------------------------- characters

def macro(gender="male", age="young", muscle=0.5, weight=0.5, extra_old=0.0):
    """MakeHuman-style macro blend. muscle/weight: 0 = min, 0.5 = average, 1 = max."""
    t = [("macrodetails/caucasian-%s-young" % gender, 1.0 - extra_old)]
    if extra_old > 0:
        t.append(("macrodetails/caucasian-%s-old" % gender, extra_old))
    names = ["minmuscle", "averagemuscle", "maxmuscle"]
    wnames = ["minweight", "averageweight", "maxweight"]

    def split(x):
        if x <= 0.5:
            return [(0, 1 - x * 2), (1, x * 2)]
        return [(1, 2 - x * 2), (2, x * 2 - 1)]
    for mi, mw in split(muscle):
        for wi, ww in split(weight):
            w = mw * ww
            if w > 1e-4 and not (mi == 1 and wi == 1):
                t.append(("macrodetails/universal-%s-%s-%s-%s" % (gender, age, names[mi], wnames[wi]), w))
    return t


def both(name, w):
    return [(name.replace("$", "r"), w), (name.replace("$", "l"), w)]


def ideal(gender="male"):
    return [("macrodetails/proportions/%s-young-averagemuscle-averageweight-idealproportions" % gender, 1.0)]


BROWN_EYES = (0.32, 0.2, 0.1)
CHARACTERS = {
    "human": dict(targets=macro() + ideal(), height=1.78, outfit=dict(sleeves="short"), hair=["short", "long", "topknot"]),
    "human_lean": dict(targets=macro(muscle=0.7, weight=0.25) + ideal(), height=1.78, outfit=dict(sleeves="short"),
                       hair=["short", "long", "topknot"]),
    "human_broad": dict(targets=macro(muscle=0.95, weight=0.65) + ideal(), height=1.8, outfit=dict(sleeves="short"),
                        hair=["short", "long", "topknot"]),
    "human_female": dict(targets=macro("female", muscle=0.6, weight=0.4) + ideal("female"), height=1.7,
                         outfit=dict(sleeves="short"), hair=["long", "short", "topknot"]),
    "amir": dict(targets=macro(muscle=0.85, weight=0.2) + ideal() + both("ears/$-ear-scale-decr", 1.0),
                 height=1.8, outfit=dict(sleeves="none", forearm_fur=True), hair=["long"], ears="wolf",
                 claws=0.022, tail=True, iris=(0.62, 0.42, 0.12)),
    "burrok": dict(targets=macro(muscle=1.0, weight=0.85) + [("torso/torso-scale-horiz-incr", 0.6),
                   ("neck/neck-scale-horiz-incr", 1.0), ("neck/neck-scale-depth-incr", 0.8),
                   ("head/head-fat-incr", 0.4)] + both("armslegs/$-hand-scale-incr", 1.0)
                   + both("ears/$-ear-scale-decr", 1.0),
                   height=2.75, outfit=dict(sleeves="none", forearm_fur=True, hand_fur=True), hair=["long"],
                   beard=0.03, ears="bear", paws=True, claws=0.03, iris=(0.28, 0.17, 0.08)),
    "vapouriun": dict(targets=macro(muscle=0.6, weight=0.15) + ideal() + both("ears/$-ear-shape-pointed", 1.0)
                      + both("ears/$-ear-scale-incr", 0.5) + [("head/head-scale-vert-incr", 0.3)],
                      height=1.74, outfit=dict(sleeves="none", hem=0.25), hair=[], fins=True, skin_detail="scales",
                      iris=(0.35, 0.8, 0.85)),
    "gouran": dict(targets=macro(muscle=0.1, weight=0.9, extra_old=0.45) + [
        ("stomach/stomach-pregnant-incr", 0.9), ("nose/nose-scale-horiz-incr", 0.7), ("nose/nose-volume-incr", 1.0),
        ("nose/nose-scale-depth-incr", 0.6), ("nose/nose-scale-vert-incr", 0.4), ("armslegs/upperlegs-height-decr", 1.0),
        ("armslegs/lowerlegs-height-decr", 1.0), ("head/head-fat-incr", 0.6), ("head/head-scale-horiz-incr", 0.4),
        ("eyebrows/eyebrows-trans-down", 0.8), ("chin/chin-prominent-incr", 0.5)]
        + both("eyes/$-eye-scale-decr", 0.7),
        height=1.3, outfit=dict(sleeves="long", robe=True), hair=["short"], beard=0.11, hood=True,
        iris=(0.45, 0.52, 0.56), eye_scale=0.8),
    "gyria": dict(targets=macro(muscle=0.55, weight=0.0) + ideal() + [("torso/torso-scale-horiz-decr", 0.6)]
                  + both("ears/$-ear-shape-pointed", 1.0) + both("ears/$-ear-scale-incr", 0.8)
                  + [("chin/chin-prominent-incr", 0.4), ("head/head-scale-horiz-decr", 0.3)],
                  height=1.86, outfit=dict(sleeves="none"), hair=["topknot"], tusks=0.014, iris=(0.75, 0.55, 0.1)),
    "gyria_boss": dict(targets=macro(muscle=1.0, weight=0.55) + [("torso/torso-scale-horiz-incr", 0.5),
                       ("neck/neck-scale-horiz-incr", 0.8), ("chin/chin-prominent-incr", 0.8)]
                       + both("ears/$-ear-shape-pointed", 1.0) + both("ears/$-ear-scale-incr", 0.8),
                       height=2.7, outfit=dict(sleeves="none"), hair=["topknot", "mohawk"], tusks=0.032, iris=(0.85, 0.35, 0.08)),
}


# ----------------------------------------------------------------- body construction

class Body:
    def __init__(self, base, rig, spec):
        self.V0, self.VT, self.groups = base
        self.rig = rig
        self.spec = spec
        V = self.V0.copy()
        for name, w in spec["targets"]:
            idx, d = load_target(name)
            V[idx] += d * w
        self.joints = {k: V[np.array(v)].mean(0) for k, v in rig.joint_verts.items()}
        self.V = V
        self._pose()
        self._to_meters()

    def head(self, b):
        return self.joints[b + "____head"]

    def tail(self, b):
        return self.joints[b + "____tail"]

    # -- re-pose from the A-pose: arms hang down, legs together, hands grip
    def _pose(self):
        rig = self.rig
        local = {b: np.eye(3) for b in rig.order}
        gl = {}

        def set_global_dir(bone, child_head_name, target, parent_global):
            d = self.head(child_head_name) - self.head(bone)
            g = rot_between(d, target)
            local[bone] = parent_global.T @ g
            return g
        for s, sx in (("L", 1.0), ("R", -1.0)):
            out = math.radians(9.0)
            down = np.array([sx * math.sin(out), -math.cos(out), 0.0])
            g_up = set_global_dir("upperarm01." + s, "lowerarm01." + s, down, np.eye(3))
            set_global_dir("lowerarm01." + s, "wrist." + s, down + np.array([0, 0, 0.12]), g_up)
            leg_dir = np.array([sx * 0.035, -1.0, 0.0])
            g_leg = set_global_dir("upperleg01." + s, "lowerleg01." + s, leg_dir, np.eye(3))
            set_global_dir("lowerleg01." + s, "foot." + s, leg_dir + np.array([0, 0, -0.02]), g_leg)
            # Relaxed grip: curl the four fingers around the knuckle line.
            side = self.head("finger5-1." + s) - self.head("finger2-1." + s)
            for f in range(2, 6):
                for seg, ang in ((1, 1.0), (2, 1.25), (3, 0.8)):
                    b = "finger%d-%d.%s" % (f, seg, s)
                    tip = self.tail(b) - self.head(b)
                    best = None
                    for sign in (1.0, -1.0):
                        r = axis_angle(side, sign * ang)
                        p = self.head(b) + r @ tip
                        dist = np.linalg.norm(p - self.head("finger1-1." + s))
                        if best is None or dist < best[0]:
                            best = (dist, r)
                    local[b] = best[1]
            for seg in (2, 3):
                b = "finger1-%d.%s" % (seg, s)
                tip = self.tail(b) - self.head(b)
                best = None
                for sign in (1.0, -1.0):
                    r = axis_angle(side, sign * 0.5)
                    dist = np.linalg.norm(self.head(b) + r @ tip - self.head("finger3-1." + s))
                    if best is None or dist < best[0]:
                        best = (dist, r)
                local[b] = best[1]
        # Forward kinematics with identity rest orientations.
        new_head, M = {}, {}
        for b in rig.order:
            p = rig.bones[b]["parent"]
            h = self.head(b)
            if p is None:
                gl[b] = local[b]
                new_head[b] = h
            else:
                gl[b] = gl[p] @ local[b]
                new_head[b] = new_head[p] + gl[p] @ (h - self.head(p))
            M[b] = (gl[b], new_head[b], h)
        V = self.V
        out = np.zeros_like(V)
        wsum = np.zeros(len(V))
        for b, lst in rig.weights.items():
            if b not in M:
                continue
            arr = np.array(lst)
            idx = arr[:, 0].astype(int)
            w = arr[:, 1]
            R, nh, h = M[b]
            out[idx] += w[:, None] * ((V[idx] - h) @ R.T + nh)
            wsum[idx] += w
        out /= np.maximum(wsum, 1e-9)[:, None]
        self.V = out
        new_joints = {}
        for k in self.joints:
            b, kind = k.split("____")
            R, nh, h = M[b]
            new_joints[k] = (self.joints[k] - h) @ R.T + nh
        self.joints = new_joints

    def _to_meters(self):
        body_idx = self.body_vertex_indices()
        ys = self.V[body_idx, 1]
        h = ys.max() - ys.min()
        s = self.spec["height"] / h
        shift = np.array([0.0, -ys.min(), 0.0])
        self.scale = s
        self.V = (self.V + shift) * s
        self.joints = {k: (v + shift) * s for k, v in self.joints.items()}

    def body_vertex_indices(self):
        return np.array(sorted({i for f in self.groups["body"] for i, _ in f}))

    # -- skin weights for the game rig
    def game_weights(self, extra_bones):
        names = [b[0] for b in GAME_BONES] + extra_bones
        W = np.zeros((len(self.V), len(names)))
        col = {n: i for i, n in enumerate(names)}
        for b, lst in self.rig.weights.items():
            if b not in self.rig.bones:
                continue
            arr = np.array(lst)
            idx = arr[:, 0].astype(int)
            w = arr[:, 1]
            a = self.rig.anchor(b)
            if b.startswith("shoulder01"):
                W[idx, col[a]] += w * 0.5
                W[idx, col["UpperArm_" + b[-1]]] += w * 0.5
            else:
                W[idx, col[a]] += w
        return names, W


def vertex_normals(P, faces, n):
    N = np.zeros((n, 3))
    for f in faces:
        idx = [i for i, _ in f]
        pts = P[idx]
        if len(idx) == 4:
            nn = np.cross(pts[2] - pts[0], pts[3] - pts[1])
        else:
            nn = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        for i in idx:
            N[i] += nn
    return normalize(N)


class Part:
    """One mesh node: a list of (material, positions, normals, uvs, colors, joints, weights, triangles)."""

    def __init__(self, name):
        self.name = name
        self.prims = []

    def add(self, material, pos, nrm, uv, col, jnt, wgt, tris):
        if len(tris):
            self.prims.append((material, np.asarray(pos, np.float32), np.asarray(nrm, np.float32),
                               np.asarray(uv, np.float32), np.asarray(col, np.float32),
                               np.asarray(jnt, np.uint8), np.asarray(wgt, np.float32), np.asarray(tris, np.uint32)))


def top4(W):
    order = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, order, axis=1)
    w = w / np.maximum(w.sum(1, keepdims=True), 1e-9)
    return order.astype(np.uint8), w


def faces_to_prim(faces, P, N, VT, C, J, Wt, flip_uv=True):
    """Converts OBJ quads (vertex, uv) to an indexed triangle primitive."""
    remap, pos, nrm, uv, col, jnt, wgt, tris = {}, [], [], [], [], [], [], []
    for f in faces:
        ids = []
        for vi, ti in f:
            key = (vi, ti)
            if key not in remap:
                remap[key] = len(pos)
                pos.append(P[vi])
                nrm.append(N[vi])
                t = VT[ti] if len(VT) else (0, 0)
                uv.append((t[0], 1.0 - t[1]) if flip_uv else t)
                col.append(C[vi])
                jnt.append(J[vi])
                wgt.append(Wt[vi])
            ids.append(remap[key])
        for k in range(1, len(ids) - 1):
            tris.append((ids[0], ids[k], ids[k + 1]))
    return pos, nrm, uv, col, jnt, wgt, tris


def build_character(name, spec, base, rig):
    body = Body(base, rig, spec)
    V = body.V
    n = len(V)
    groups = body.groups
    extra = ["Tail%d" % i for i in range(TAIL_BONES)] if spec.get("tail") else []
    bone_names, W = body.game_weights(extra)
    bcol = {b: i for i, b in enumerate(bone_names)}
    dom = np.argmax(W, axis=1)
    J = body.head
    y = V[:, 1]
    outfit = spec.get("outfit", {})

    def bone_is(*names):
        return np.isin(dom, [bcol[b] for b in names])

    # Key heights.
    hips_y = J("root")[1]
    spine_y = J("spine04")[1]
    chest_y = J("spine02")[1]
    neck_y = J("neck01")[1]
    head_y = J("head")[1]
    eye_c = {s: J("eye." + s) for s in SIDES}
    knee_y = (J("lowerleg01.L")[1] + J("lowerleg01.R")[1]) * 0.5
    ankle_y = (J("foot.L")[1] + J("foot.R")[1]) * 0.5
    belt_y = spine_y + (chest_y - spine_y) * 0.12
    boot_y = ankle_y + (knee_y - ankle_y) * (0.55 if outfit.get("robe") else 0.62)
    s = spec["height"] / 1.78

    def classify(X, dx):
        def isb(*names):
            return np.isin(dx, [bcol[b] for b in names])
        yy = X[:, 1]
        region = np.array(["skin"] * len(X), dtype=object)
        torso = isb("Chest", "Spine", "Clavicle_L", "Clavicle_R")
        region[torso] = "top"
        hipsm = isb("Hips")
        region[hipsm & (yy > belt_y)] = "top"
        region[hipsm & (yy <= belt_y)] = "pants"
        neckm = isb("Neck")
        region[neckm & (yy < neck_y + (head_y - neck_y) * 0.25)] = "top"
        sleeves = outfit.get("sleeves", "short")
        for sd in SIDES:
            up = isb("UpperArm_" + sd)
            lo = isb("LowerArm_" + sd)
            sh = J("upperarm01." + sd)
            el = J("lowerarm01." + sd)
            t = np.einsum("ij,j->i", X - sh, el - sh) / np.dot(el - sh, el - sh)
            if sleeves == "short":
                region[up & (t < 0.55)] = "top"
            elif sleeves == "long":
                region[up | lo] = "top"
            else:
                region[up & (t < 0.12)] = "top"
            if outfit.get("forearm_fur"):
                region[lo] = "fur"
                if sleeves == "none":
                    region[up & (t > 0.45)] = "fur"
            if outfit.get("hand_fur"):
                region[isb("Hand_" + sd)] = "fur"
            region[isb("UpperLeg_" + sd)] = "pants"
            lleg = isb("LowerLeg_" + sd)
            region[lleg] = "pants"
            region[lleg & (yy < boot_y)] = "boots"
            region[isb("Foot_" + sd)] = "boots"
        if outfit.get("top") == "vest":
            # Open vest: bare chest and belly in front.
            front = X[:, 2] > np.interp(yy, [belt_y, chest_y], [0.0, 0.02 * s]) + 0.03 * s
            bare = torso & front & (np.abs(X[:, 0]) < 0.09 * s) & (yy < J("neck01")[1] - 0.02 * s)
            region[bare] = "skin"
        torso_band = torso | hipsm
        region[torso_band & (np.abs(yy - belt_y) < 0.028 * s)] = "belt"
        if outfit.get("robe"):
            region[(region == "top") | (region == "belt")] = "robe"
            region[torso_band & (np.abs(yy - belt_y) < 0.022 * s)] = "belt"

        return region, torso, hipsm, neckm

    region, torso, hipsm, neckm = classify(V, dom)
    body_faces = groups["body"]
    fidx = np.array([[i for i, _ in f] for f in body_faces])
    fcent = V[fidx].mean(1)
    fdom = np.argmax(W[fidx].sum(1), axis=1)
    face_mat = list(classify(fcent, fdom)[0])

    # Inflate cloth over the body, smoothed so seams blend.
    off_by = {"skin": 0.0, "top": 0.010, "robe": 0.012, "pants": 0.0065, "boots": 0.012, "belt": 0.017, "fur": 0.007}
    off = np.zeros(n)
    for f, m in zip(body_faces, face_mat):
        for i, _ in f:
            off[i] = max(off[i], off_by[m])
    adj = [[] for _ in range(n)]
    for f in body_faces:
        ids = [i for i, _ in f]
        for a in range(len(ids)):
            adj[ids[a]].append(ids[(a + 1) % len(ids)])
            adj[ids[a]].append(ids[a - 1])
    for _ in range(2):
        off = np.array([0.5 * off[i] + 0.5 * (np.mean(off[a]) if a else off[i]) for i, a in enumerate(adj)])
    N0 = vertex_normals(V, body_faces, n)

    # Burrok paws: enlarge the hands around the wrists.
    if spec.get("paws"):
        for sd in SIDES:
            hm = W[:, bcol["Hand_" + sd]]
            c = J("wrist." + sd)
            V = V + ((V - c) * 0.32) * hm[:, None]
    P = V + N0 * (off * s)[:, None]
    # Boots: smooth the toes and ankle bones away so feet read as footwear.
    boot_v = np.zeros(n, bool)
    for f, m in zip(body_faces, face_mat):
        if m == "boots":
            for i, _ in f:
                boot_v[i] = True
    foot_v = boot_v & (y < ankle_y + 0.07 * s)
    for _ in range(30):
        avg = np.array([P[a].mean(0) if a else P[i] for i, a in enumerate(adj)])
        P[foot_v] = P[foot_v] * 0.4 + avg[foot_v] * 0.6
    N = vertex_normals(P, body_faces, n)

    # Face paint masks: r = eyebrows, g = lips, b = eye-socket shading, a = beard shadow.
    C = np.zeros((n, 4))
    C[:, 3] = 1.0
    headm = bone_is("Head")
    mouth = np.array([0.0, (J("oris06")[1] + J("oris01")[1]) * 0.5, J("oris06")[2]])
    mouth_w = abs(J("oris03.L")[0]) * 1.1 + 0.002 * s
    lip_h = (J("oris06")[1] - J("oris01")[1]) * 0.42 + 0.001 * s
    dx = (V[:, 0] - mouth[0]) / mouth_w
    dy = (V[:, 1] - mouth[1]) / lip_h
    front = V[:, 2] > mouth[2] - 0.02 * s
    C[:, 1] = np.where(headm & front, np.clip(1.25 - (dx * dx + dy * dy) * 1.25, 0, 1), 0)
    for sd in SIDES:
        e = eye_c[sd]
        bx = (V[:, 0] - (e[0] + 0.002 * s * (1 if sd == "L" else -1))) / (0.024 * s)
        by = (V[:, 1] - (e[1] + 0.017 * s + 0.004 * s * np.abs(bx))) / (0.0055 * s)
        brow = np.clip(1.3 - (bx * bx * bx * bx + by * by), 0, 1)
        C[:, 0] = np.maximum(C[:, 0], np.where(headm & (V[:, 2] > e[2] - 0.015 * s), brow, 0))
        ex = (V[:, 0] - e[0]) / (0.022 * s)
        ey = (V[:, 1] - e[1]) / (0.016 * s)
        C[:, 2] = np.maximum(C[:, 2], np.where(headm, np.clip(1.0 - (ex * ex + ey * ey), 0, 1) * 0.8, 0))

    Jt, Wt = top4(W)
    # Skirts and robes hang from the hips instead of stretching with the legs.
    Ws = W * 0.4
    Ws[:, bcol["Hips"]] += 0.6
    Js, Wss = top4(Ws)
    model_parts = []

    # ---- body
    body_part = Part("Body")
    white = np.ones((n, 4))
    foot_bones = [bcol["Foot_L"], bcol["Foot_R"]]
    in_foot = np.isin(dom, foot_bones) & (y < ankle_y + 0.01 * s)
    for m in ["skin", "top", "robe", "pants", "boots", "belt", "fur"]:
        fs = [f for f, fm in zip(body_faces, face_mat) if fm == m and not (fm == "boots" and all(in_foot[i] for i, _ in f))]
        if fs:
            body_part.add(m, *faces_to_prim(fs, P, N, body.VT, C if m == "skin" else white, Jt, Wt))

    for sd in SIDES:
        body_part.add("boots", *make_boot(P, np.where(np.isin(dom, [bcol["Foot_" + sd]]))[0], ankle_y, s,
                                          bcol["Foot_" + sd], bcol["LowerLeg_" + sd]))

    # ---- eyes (spheres in the sockets)
    eye_parts = []
    for sd in SIDES:
        g = groups["helper-%s-eye" % sd.lower()]
        idx = np.array(sorted({i for f in g for i, _ in f}))
        c = V[idx].mean(0)
        r = (V[idx].max(0) - V[idx].min(0)).max() * 0.5 * spec.get("eye_scale", 1.0)
        eye_parts.append(make_eye(c, r, spec.get("iris", BROWN_EYES), bcol["Head"]))
    for e in eye_parts:
        body_part.add("eyes", *e)

    head_idx = np.where(headm)[0]
    head_c = V[head_idx].mean(0)
    head_c[1] = eye_c["L"][1] + 0.01 * s
    top_y = V[head_idx, 1].max()

    # ---- people features baked into the body
    if spec.get("ears") in ("wolf", "bear"):
        for sd, sx in (("L", 1.0), ("R", -1.0)):
            body_part.add("fur", *make_animal_ear(V, head_idx, head_c, sx, spec["ears"], s, bcol["Head"]))
    if spec.get("claws"):
        for sd in SIDES:
            for f in range(1, 6):
                b = "finger%d-3.%s" % (f, sd)
                tip = body.tail(b)
                d = normalize(body.tail(b) - body.head(b))
                L = spec["claws"] * (0.7 if f == 1 else 1.0) * (spec["height"] / 1.8 if spec.get("paws") else 1.0)
                body_part.add("claw", *make_cone(tip - d * L * 0.25, d, L, L * 0.28, bcol["Hand_" + sd], curl=0.4))
    if spec.get("tusks"):
        for sx in (1.0, -1.0):
            base = np.array([sx * mouth_w * 0.72, mouth[1] - lip_h * 1.1, mouth[2] - 0.004 * s])
            d = normalize(np.array([sx * 0.25, 1.0, 0.35]))
            L = spec["tusks"]
            body_part.add("claw", *make_cone(base, d, L, L * 0.3, bcol["Head"], curl=-0.3))
    if spec.get("fins"):
        body_part.add("fin", *make_crest(V, head_idx, head_c, s, bcol["Head"]))
        for sx in (1.0, -1.0):
            body_part.add("fin", *make_ear_fin(V, head_idx, head_c, sx, s, bcol["Head"]))
    model_parts.append(body_part)

    # ---- hair variants: shells over the scalp of the (welded) body mesh
    hair_c = np.ones((n, 4))
    eye_y = eye_c["L"][1]
    nape_y = J("neck03")[1] + 0.01 * s
    ang = np.degrees(np.arctan2(np.abs(V[:, 0] - head_c[0]), V[:, 2] - head_c[2]))
    hairline = np.interp(ang, [0, 50, 72, 108, 140, 180],
                         [eye_y + 0.05 * s, eye_y + 0.043 * s, eye_y + 0.046 * s, eye_y + 0.046 * s,
                          eye_y - 0.015 * s, nape_y])
    scalp = (headm | neckm) & (y > hairline - 0.012 * s)
    scalp_faces = [f for f in body_faces if any(scalp[i] for i, _ in f)]
    edge = smoothstep(-0.004 * s, 0.012 * s, y - hairline)
    vol = (0.0015 * s + (0.0045 * s + 0.011 * s * smoothstep(eye_y, top_y, y)) * edge)
    hair_shell = V + N0 * vol[:, None]
    hair_c = np.ones((n, 4))
    hair_c[:, 3] = smoothstep(-0.006 * s, 0.004 * s, y - hairline)
    for style in spec.get("hair", []):
        faces = scalp_faces
        P_h = hair_shell
        if style == "mohawk":
            faces = [f for f in scalp_faces if min(abs(V[i, 0] - head_c[0]) for i, _ in f) < 0.022 * s]
            P_h = V + N0 * (vol + 0.016 * s * smoothstep(eye_y - 0.02 * s, top_y, y) * smoothstep(0.024 * s, 0.006 * s, np.abs(V[:, 0] - head_c[0])))[:, None]
            mo_c = hair_c.copy()
            mo_c[:, 3] *= smoothstep(0.024 * s, 0.016 * s, np.abs(V[:, 0] - head_c[0]))
            part = Part("Hair_" + style)
            part.add("hair", *faces_to_prim(faces, P_h, vertex_normals(P_h, faces, n), body.VT, mo_c, Jt, Wt))
            model_parts.append(part)
            continue
        part = Part("Hair_" + style)
        part.add("hair", *faces_to_prim(faces, P_h, vertex_normals(P_h, faces, n), body.VT, hair_c, Jt, Wt))
        if style == "topknot":
            c = np.array([0.0, top_y + 0.012 * s, head_c[2] - 0.04 * s])
            part.add("hair", *make_sphere(c, 0.03 * s, bcol["Head"], (1, 1, 1)))
        if style == "long":
            part.add("hair", *make_hair_drape(V, head_idx, head_c, eye_y, J("neck01")[1] - 0.06 * s, s, bcol))
        model_parts.append(part)
    if spec.get("hood"):
        hood_line = np.interp(ang, [0, 60, 90, 180], [eye_y + 0.055 * s, eye_y + 0.02 * s, J("jaw")[1], neck_y])
        hood_m = (headm | neckm) & (y > hood_line - 0.012 * s)
        hood_faces = [f for f in body_faces if any(hood_m[i] for i, _ in f)]
        hood_c = np.ones((n, 4))
        hood_c[:, 3] = smoothstep(-0.006 * s, 0.004 * s, y - hood_line)
        hp = V + N0 * (0.02 * s + 0.012 * s * smoothstep(eye_y, top_y, y))[:, None]
        part = Part("Hood")
        part.add("hood", *faces_to_prim(hood_faces, hp, vertex_normals(hp, hood_faces, n), body.VT, hood_c, Jt, Wt))
        # Peak at the back of the hood.
        tip = np.array([0.0, eye_y + 0.02 * s, V[head_idx, 2].min() - 0.06 * s])
        part.add("hood", *make_cone(tip + np.array([0, 0.02 * s, 0.05 * s]), np.array([0, -0.35, -1.0]), 0.06 * s,
                                    0.04 * s, bcol["Head"]))
        model_parts.append(part)

    # ---- beard
    if spec.get("beard"):
        model_parts.append(make_beard(body, V, N0, body_faces, headm | neckm, mouth, mouth_w, lip_h, eye_y, ang, s,
                                      spec["beard"], Jt, Wt, n, bcol))

    # ---- cloak (optional, the Emoria Guild cape)
    if name.startswith("human"):
        model_parts.append(make_cloak(V, J, s, bcol))

    # ---- robe skirt (Gouran)
    if outfit.get("robe"):
        sg = groups["helper-skirt"]
        SN = vertex_normals(V, sg, n)
        sp = V + SN * (0.012 * s)
        # Flare the hem a little.
        flare = smoothstep(hips_y, ankle_y, V[:, 1]) * 0.05 * s
        sp[:, 0] += np.sign(V[:, 0]) * flare * 0.6
        sp[:, 2] += np.where(V[:, 2] > 0, flare * 0.5, -flare * 0.5)
        skirt = Part("Body_robe")
        skirt.add("robe", *faces_to_prim(sg, sp, vertex_normals(sp, sg, n), body.VT, hair_c, Js, Wss))
        model_parts.append(skirt)

    # ---- tunic / kilt hem below the belt (reads clearly as clothing)
    hem = outfit.get("hem", 0.5)
    if not outfit.get("robe") and hem > 0:
        sg = groups["helper-skirt"]
        hem_y = belt_y - (belt_y - knee_y) * hem
        keep = [f for f in sg if min(V[i, 1] for i, _ in f) > hem_y - 0.02 * s]
        SN = vertex_normals(V, sg, n)
        sp = V + SN * (0.016 * s)
        flare = smoothstep(belt_y, hem_y, V[:, 1]) * 0.025 * s
        sp[:, 0] += np.sign(V[:, 0]) * flare
        sp[:, 2] += np.where(V[:, 2] > 0, flare * 0.6, -flare * 0.6)
        hc = np.ones((n, 4))
        hc[:, 3] = smoothstep(hem_y - 0.004 * s, hem_y + 0.004 * s, V[:, 1])
        skirt = Part("Body_hem")
        skirt.add(outfit.get("hem_material", "tunic"), *faces_to_prim(keep, sp, vertex_normals(sp, keep, n), body.VT, hc, Js, Wss))
        model_parts.append(skirt)

    # ---- tail
    tail_bones = []
    if spec.get("tail"):
        part, tail_bones = make_tail(V, body, s, spec["height"], bcol)
        model_parts.append(part)

    # Game skeleton heads.
    heads = {gb: body.head(mh) for gb, _, mh in GAME_BONES}
    parents = {gb: p for gb, p, _ in GAME_BONES}
    for i, (h, p) in enumerate(tail_bones):
        heads["Tail%d" % i] = h
        parents["Tail%d" % i] = p
    meta = {
        "height": spec["height"],
        "eye_y": float(eye_c["L"][1]),
        "head_top": float(top_y),
        "head_center": [float(-head_c[0]), float(head_c[1]), float(-head_c[2])],
    }
    write_glb(os.path.join(OUT, name + ".glb"), bone_names, heads, parents, model_parts, meta)
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta


# ----------------------------------------------------------------- generated features

def _grid_prim(rows, bone, material_color=(1, 1, 1, 1), close=False, weights_fn=None):
    """rows: list of rings/rows of points (each an array (k,3)). Builds a quad grid."""
    rows = [np.asarray(r) for r in rows]
    k = len(rows[0])
    pos = np.concatenate(rows)
    tris = []
    cols = k if close else k - 1
    for r in range(len(rows) - 1):
        for c in range(cols):
            a = r * k + c
            b = r * k + (c + 1) % k
            tris += [(a, a + k, b), (b, a + k, b + k)]
    nrm = np.zeros_like(pos)
    for t in tris:
        p0, p1, p2 = pos[list(t)]
        nn = np.cross(p1 - p0, p2 - p0)
        for i in t:
            nrm[i] += nn
    nrm = normalize(nrm)
    n = len(pos)
    uv = np.zeros((n, 2))
    for r in range(len(rows)):
        for c in range(k):
            uv[r * k + c] = (c / max(k - 1, 1), r / max(len(rows) - 1, 1))
    col = np.tile(np.array(material_color, float), (n, 1))
    if weights_fn is None:
        jnt = np.tile(np.array([bone, 0, 0, 0], np.uint8), (n, 1))
        wgt = np.tile(np.array([1, 0, 0, 0], float), (n, 1))
    else:
        jnt, wgt = weights_fn(pos, len(rows), k)
    return pos, nrm, uv, col, jnt, wgt, tris


def make_sphere(c, r, bone, color, rings=10, segs=14):
    rows = []
    for i in range(rings + 1):
        th = math.pi * i / rings
        rows.append([c + r * np.array([math.sin(th) * math.cos(2 * math.pi * j / segs), math.cos(th),
                                       math.sin(th) * math.sin(2 * math.pi * j / segs)]) for j in range(segs)])
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, bone, (*color, 1), close=True)
    _, tris = orient(pos, tris, c)
    return pos, normalize(pos - c), uv, col, jnt, wgt, tris


def make_eye(c, r, iris, bone):
    rings, segs = 14, 18
    rows, cols = [], []
    for i in range(rings + 1):
        th = math.pi * i / rings  # 0 at the front (+Z in MakeHuman space)
        row, crow = [], []
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            d = np.array([math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)])
            row.append(c + r * d)
            ang = th
            if ang < 0.2:
                crow.append((0.02, 0.02, 0.02, 1))
            elif ang < 0.52:
                k = (ang - 0.2) / 0.32
                crow.append((iris[0] * (0.6 + 0.6 * k), iris[1] * (0.6 + 0.6 * k), iris[2] * (0.6 + 0.6 * k), 1))
            else:
                crow.append((0.93, 0.9, 0.86, 1))
        rows.append(row)
        cols.append(crow)
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, bone, close=True)
    col = np.array([cc for row in cols for cc in row], float)
    _, tris = orient(pos, tris, c)
    return pos, normalize(pos - c), uv, col, jnt, wgt, tris


def scalp_point(V, head_idx, c, d):
    P = V[head_idx]
    rel = normalize(P - c)
    score = rel @ normalize(d)
    i = head_idx[np.argmax(score)]
    return V[i]


def make_animal_ear(V, head_idx, c, sx, kind, s, bone):
    if kind == "wolf":
        d = np.array([sx * 0.55, 0.82, -0.12])
        base = scalp_point(V, head_idx, c, d) - normalize(d) * 0.006 * s
        axis = normalize(np.array([sx * 0.45, 1.0, -0.15]))
        height, width, depth, steps = 0.095 * s, 0.065 * s, 0.032 * s, 8
        prof = lambda t: (1 - t) ** 0.85
    else:
        d = np.array([sx * 0.7, 0.7, -0.08])
        base = scalp_point(V, head_idx, c, d)
        axis = normalize(np.array([sx * 0.55, 1.0, -0.05]))
        side = normalize(np.cross(axis, np.array([0, 0, 1.0])))
        fwd = normalize(np.cross(side, axis))
        rows = []
        for i in range(9):
            th = math.pi * i / 8
            rows.append([base + axis * (0.034 * s * math.cos(th) * -1 + 0.012 * s)
                         + side * 0.032 * s * math.sin(th) * math.cos(2 * math.pi * j / 12)
                         + fwd * 0.016 * s * math.sin(th) * math.sin(2 * math.pi * j / 12) for j in range(12)])
        pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, bone, close=True)
        for i in range(len(pos)):
            if np.dot(pos[i] - base, fwd) > 0.006 * s:
                col[i] = (0.62, 0.5, 0.45, 1)
        nrm, tris = orient(pos, tris, base + axis * 0.012 * s)
        return pos, nrm, uv, col, jnt, wgt, tris
    if False:
        base = scalp_point(V, head_idx, c, d) - normalize(d) * 0.006 * s
        axis = normalize(np.array([sx * 0.6, 1.0, -0.05]))
        height, width, depth, steps = 0.05 * s, 0.06 * s, 0.03 * s, 8
        prof = lambda t: math.sqrt(max(0.0, 1 - t * t)) * (1 - 0.15 * t)
    side = normalize(np.cross(axis, np.array([0, 0, 1.0])))
    fwd = normalize(np.cross(side, axis))
    if fwd[2] < 0:
        fwd = -fwd
    rows = []
    segs = 12
    for i in range(steps + 1):
        t = i / steps
        w = width * 0.5 * prof(t)
        dd = depth * prof(t)
        ctr = base + axis * height * t
        row = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            # Cupped cross-section: a crescent open to the front.
            cs, sn = math.cos(a), math.sin(a)
            z = dd * (sn * 0.5 - 0.15 * (1 - abs(cs)))
            row.append(ctr + side * w * cs + fwd * z)
        rows.append(row)
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, bone, close=True)
    # Lighter inner ear (vertex colour = mask for the fur shader).
    for i in range(len(pos)):
        if np.dot(pos[i] - (base + axis * height * 0.4), fwd) > 0 and kind == "wolf":
            col[i] = (1.0, 0.75, 0.7, 1)
    nrm, tris = orient(pos, tris, base + axis * height * 0.4)
    return pos, nrm, uv, col, jnt, wgt, tris


def orient(pos, tris, center=None):
    """Flips the winding of a closed generated shape so its faces point outwards."""
    pos = np.asarray(pos)
    c = pos.mean(0) if center is None else center
    nrm = fix_normals(pos, tris)
    if np.mean(np.sum(nrm * (pos - c), axis=1)) < 0:
        tris = [(a, cc, b) for a, b, cc in tris]
        nrm = -nrm
    return nrm, tris


def fix_normals(pos, tris):
    nrm = np.zeros_like(pos)
    for t in tris:
        p0, p1, p2 = pos[list(t)]
        nn = np.cross(p1 - p0, p2 - p0)
        for i in t:
            nrm[i] += nn
    return normalize(nrm)


def make_cone(base, d, L, r, bone, curl=0.0, segs=6, rings=4):
    d = normalize(d)
    side = normalize(np.cross(d, np.array([0.0, 0.0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0, 0])))
    up = np.cross(side, d)
    rows = []
    for i in range(rings + 1):
        t = i / rings
        ctr = base + d * L * t + up * curl * L * t * t * 0.5
        rr = r * (1 - t) + 0.0004
        rows.append([ctr + rr * (side * math.cos(2 * math.pi * j / segs) + up * math.sin(2 * math.pi * j / segs))
                     for j in range(segs)])
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, bone, close=True)
    nrm, tris = orient(pos, tris, base + d * L * 0.3)
    return pos, nrm, uv, col, jnt, wgt, tris


def make_crest(V, head_idx, c, s, bone):
    rows = []
    steps = 14
    for i in range(steps + 1):
        t = i / steps
        # From the forehead (front is +Z in MakeHuman space) over the crown to the nape.
        ang = math.radians(50 - 160 * t)
        p = scalp_point(V, head_idx, c, np.array([0.0, math.cos(ang), math.sin(ang)]))
        h = 0.05 * s * math.sin(math.pi * min(1.0, t * 1.1)) ** 0.7 + 0.004 * s
        out = normalize(p - c)
        rows.append([p - out * 0.004 * s, p + out * h * 0.55, p + out * h])
    rows = [np.array(r) for r in rows]
    cols = np.array(rows).transpose(1, 0, 2)
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(list(cols), bone, close=False)
    nrm = fix_normals(pos, tris)
    # Ribs: darker stripes for the shader (vertex colour).
    for i in range(len(pos)):
        k = i % (steps + 1)
        col[i] = (0.75, 0.85, 0.95, 1) if k % 2 == 0 else (1, 1, 1, 1)
    return pos, nrm, uv, col, jnt, wgt, tris


def make_ear_fin(V, head_idx, c, sx, s, bone):
    """A Vapouriun ear fin: a ribbed membrane fanning backwards from behind the ear."""
    base = scalp_point(V, head_idx, c, np.array([sx * 1.0, 0.0, -0.3])) + np.array([sx * 0.002 * s, 0, 0])
    spines = 9
    inner, outer = [], []
    for i in range(spines):
        a = math.radians(-35 + 95 * i / (spines - 1))
        d = normalize(np.array([sx * 0.35, math.sin(a), -math.cos(a)]))
        L = 0.055 * s * (0.7 + 0.45 * math.sin(math.pi * i / (spines - 1))) * (1.0 if i % 2 == 0 else 0.86)
        inner.append(base + d * L * 0.15)
        outer.append(base + d * L)
    rows = [inner, [(a + b) * 0.5 for a, b in zip(inner, outer)], outer]
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, bone, close=False)
    nrm = fix_normals(pos, tris)
    for i in range(len(pos)):
        col[i] = (0.6, 0.75, 0.9, 1) if (i % spines) % 2 == 0 else (1, 1, 1, 1)
    return pos, nrm, uv, col, jnt, wgt, tris


def make_boot(P, idx, ankle_y, s, foot_bone, leg_bone):
    """A smooth closed boot around a foot (MakeHuman toes would show through cloth)."""
    F = P[idx]
    z0, z1 = F[:, 2].min(), F[:, 2].max()
    rows, segs, steps = [], 14, 10
    for i in range(steps + 1):
        t = i / steps
        zc = z0 + (z1 - z0) * t
        band = F[np.abs(F[:, 2] - zc) < (z1 - z0) / steps]
        if len(band) == 0:
            band = F
        xc = (band[:, 0].max() + band[:, 0].min()) * 0.5
        w = (band[:, 0].max() - band[:, 0].min()) * 0.5 + 0.007 * s
        ylo = F[:, 1].min() - 0.004 * s
        yhi = min(band[:, 1].max(), ankle_y + 0.03 * s) + 0.006 * s
        if t > 0.92:  # rounded toe cap
            k = (1 - t) / 0.08
            w *= 0.55 + 0.45 * k
            yhi = ylo + (yhi - ylo) * (0.5 + 0.5 * k)
        yc, hh = (ylo + yhi) * 0.5, (yhi - ylo) * 0.5
        row = []
        for j in range(segs):
            a = 2 * math.pi * j / segs
            ca, sa = math.cos(a), math.sin(a)
            # Flat sole: squash the lower half of the section.
            yy = yc + hh * (sa if sa > 0 else max(sa, -1.0) * 1.0)
            row.append((xc + w * ca * (1.0 if sa > -0.3 else 0.96), yy, zc))
        rows.append(row)
    cap0 = [np.mean(rows[0], axis=0)] * segs
    cap1 = [np.mean(rows[-1], axis=0)] * segs
    rows = [cap0] + rows + [cap1]

    def wfn(pos, nrows, k):
        jn, wg = [], []
        for p in pos:
            a = float(np.clip((p[1] - ankle_y) / (0.04 * s), 0.0, 1.0))
            jn.append((foot_bone, leg_bone, 0, 0))
            wg.append((1 - a * 0.5, a * 0.5, 0, 0))
        return np.array(jn, np.uint8), np.array(wg, float)
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, foot_bone, close=True, weights_fn=wfn)
    nrm, tris = orient(pos, tris, np.mean(pos, axis=0))
    uv *= np.array([2.0, 2.0])
    return pos, nrm, uv, col, jnt, wgt, tris


def make_hair_drape(V, head_idx, c, eye_y, end_y, s, bcol):
    """Long hair falling from the back of the head over the neck and shoulders."""
    cols, rows_n = 13, 9
    allrel = V - c
    a_body = np.arctan2(allrel[:, 0], allrel[:, 2])
    r_body = np.hypot(allrel[:, 0], allrel[:, 2])
    P = V[head_idx]
    rel = P - c
    a_all = np.arctan2(rel[:, 0], rel[:, 2])
    rad_all = np.hypot(rel[:, 0], rel[:, 2])
    rows = []
    top = eye_y + 0.03 * s
    for r in range(rows_n + 1):
        t = r / rows_n
        yy = top + (end_y - top) * t
        row = []
        for k in range(cols):
            a = math.radians(-62 + 124 * k / (cols - 1)) + math.pi  # around the back
            da = np.abs((a_all - a + math.pi) % (2 * math.pi) - math.pi)
            band = (da < 0.25) & (np.abs(P[:, 1] - min(yy, eye_y + 0.02 * s)) < 0.03 * s)
            head_r = rad_all[band].max() if band.any() else 0.09 * s
            db = np.abs((a_body - a + math.pi) % (2 * math.pi) - math.pi)
            bb = (db < 0.12) & (np.abs(V[:, 1] - yy) < 0.015 * s)
            body_r = r_body[bb].max() if bb.any() else 0.0
            radius = max(head_r * (1.0 - 0.3 * t), body_r + 0.004 * s) + 0.01 * s
            row.append((c[0] + math.sin(a) * radius, yy, c[2] + math.cos(a) * radius))
        rows.append(row)

    def wfn(pos, nrows, k):
        jn, wg = [], []
        for r in range(nrows):
            t = r / (nrows - 1)
            for _ in range(k):
                jn.append((bcol["Head"], bcol["Neck"], bcol["Chest"], 0))
                a = max(0.0, 1 - t * 1.6)
                b = max(0.0, 1 - abs(t - 0.55) * 2.5)
                cc = max(0.0, t * 1.8 - 0.8)
                tot = a + b + cc
                wg.append((a / tot, b / tot, cc / tot, 0))
        return np.array(jn, np.uint8), np.array(wg, float)
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, 0, close=False, weights_fn=wfn)
    nrm = fix_normals(pos, tris)
    if np.mean(nrm[:, 2] * (pos[:, 2] - c[2])) < 0:
        tris = [(a, cc, b) for a, b, cc in tris]
        nrm = fix_normals(pos, tris)
    for i in range(len(pos)):
        r_, k_ = divmod(i, cols)
        side = abs(k_ / (cols - 1) * 2 - 1)
        col[i, 3] = 1.0 if r_ < rows_n else (0.0 if k_ % 2 else 0.6)
        if side > 0.95:
            col[i, 3] *= 0.3
    uv *= np.array([3.0, 4.0])
    return pos, nrm, uv, col, jnt, wgt, tris


def make_beard(body, V, N0, body_faces, region_mask, mouth, mouth_w, lip_h, eye_y, ang, s, length, Jt, Wt, n, bcol):
    """A beard shell over jaw, chin and upper lip with soft (alpha) edges; long
    beards also get a hanging lock. It never changes the face's human shape."""
    y, x, z = V[:, 1], V[:, 0], V[:, 2]
    chin_y = body.head("special04")[1]
    top = np.interp(ang, [0, 25, 45, 75, 100, 115],
                    [mouth[1] + lip_h * 2.6, mouth[1] + lip_h * 2.2, mouth[1] + lip_h * 0.6,
                     eye_y - 0.035 * s, eye_y - 0.02 * s, eye_y - 0.02 * s])
    bottom = chin_y - 0.045 * s
    lips = ((x - mouth[0]) / (mouth_w * 1.15)) ** 2 + ((y - mouth[1]) / (lip_h * 1.4)) ** 2
    alpha = smoothstep(0.004 * s, -0.004 * s, y - top) * smoothstep(bottom - 0.01 * s, bottom + 0.01 * s, y)
    alpha *= smoothstep(118, 105, ang)
    alpha *= np.where(z > mouth[2] - 0.03 * s, smoothstep(0.9, 1.3, lips), 1.0)
    alpha = np.where(region_mask, alpha, 0.0)
    sel = alpha > 0.02
    faces = [f for f in body_faces if any(sel[i] for i, _ in f) and all(region_mask[i] for i, _ in f)]
    thick = 0.003 * s + min(length, 0.03) * 0.25 * smoothstep(mouth[1], chin_y - 0.02 * s, y)
    P = V + N0 * (thick * np.clip(alpha * 1.5, 0, 1))[:, None]
    C = np.ones((n, 4))
    C[:, 3] = np.clip(alpha * 1.6, 0, 1)
    part = Part("Beard")
    part.add("beard", *faces_to_prim(faces, P, vertex_normals(P, faces, n), body.VT, C, Jt, Wt))
    if length > 0.05:
        # Hanging lock from the chin (Gouran).
        chin = np.array([0.0, chin_y - 0.01 * s, V[(np.abs(x) < 0.01 * s) & (np.abs(y - chin_y) < 0.01 * s)][:, 2].max() - 0.006 * s])
        rows, segs, steps = [], 12, 10
        for i in range(steps + 1):
            t = i / steps
            ctr = chin + np.array([0, -length * t, 0.02 * s * math.sin(t * math.pi * 0.8) - 0.03 * s * t])
            w = (0.032 * s * (1 - t) ** 0.7 + 0.004 * s)
            d = (0.022 * s * (1 - t) ** 0.8 + 0.003 * s)
            rows.append([ctr + np.array([w * math.cos(2 * math.pi * j / segs), 0, d * math.sin(2 * math.pi * j / segs)])
                         for j in range(segs)])
        pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, bcol["Head"], close=True)
        nrm, tris = orient(pos, tris, chin + np.array([0, -length * 0.5, 0]))
        uv *= np.array([2.0, 3.0])
        part.add("beard", pos, nrm, uv, col, jnt, wgt, tris)
    return part


def make_cloak(V, J, s, bcol):
    shoulder_y = (J("shoulder01.L")[1] + J("shoulder01.R")[1]) * 0.5
    half = abs(J("shoulder01.L")[0]) * 1.3
    knee_y = (J("lowerleg01.L")[1] + J("lowerleg01.R")[1]) * 0.5
    back = V[(np.abs(V[:, 1] - shoulder_y + 0.05 * s) < 0.04 * s) & (np.abs(V[:, 0]) < half)][:, 2].min()
    rows = []
    nr, nc = 12, 13
    for r in range(nr + 1):
        t = r / nr
        yy = shoulder_y + 0.02 * s - (shoulder_y - knee_y + 0.08 * s) * t
        w = half * (1.0 + 0.35 * t)
        row = []
        for c in range(nc):
            u = c / (nc - 1) * 2 - 1
            # Wraps round the shoulders at the top, hangs in soft folds below.
            zz = back - 0.03 * s - 0.08 * s * t - 0.03 * s * (1 - u * u)
            zz += (0.11 * s * (1 - t) ** 2 + 0.04 * s) * u * u
            zz -= 0.014 * s * t * math.cos(u * math.pi * 3.0) ** 2
            row.append((u * w, yy, zz))
        rows.append(row)

    def wfn(pos, nrows, k):
        jn, wg = [], []
        for r in range(nrows):
            t = r / (nrows - 1)
            for _ in range(k):
                jn.append((bcol["Chest"], bcol["Spine"], bcol["Hips"], 0))
                a = max(0.0, 1 - t * 2.2)
                b = max(0.0, 1 - abs(t - 0.45) * 2.2)
                c = max(0.0, t * 1.6 - 0.4)
                tot = a + b + c
                wg.append((a / tot, b / tot, c / tot, 0))
        return np.array(jn, np.uint8), np.array(wg, float)
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, 0, close=False, weights_fn=wfn)
    nrm = fix_normals(pos, tris)
    part = Part("Cloak")
    part.add("cloak", pos, nrm, uv, col, jnt, wgt, tris)
    return part


def make_tail(V, body, s, height, bcol):
    hip_y = body.head("root")[1]
    z_back = V[(np.abs(V[:, 0]) < 0.03 * s) & (np.abs(V[:, 1] - (hip_y + 0.08 * s)) < 0.03 * s)][:, 2].min()
    base = np.array([0.0, hip_y + 0.08 * s, z_back + 0.01 * s])
    seg = height * 0.14
    heads, prev = [], "Hips"
    for i in range(TAIL_BONES):
        heads.append((base + np.array([0, 0, -seg * i]), prev))
        prev = "Tail%d" % i
    rows, segs, steps = [], 10, 30
    total = seg * TAIL_BONES
    for i in range(steps + 1):
        t = i / steps
        ctr = base + np.array([0, 0, -total * t])
        r = (0.025 + 0.035 * math.sin(math.pi * min(1.0, t * 1.25)) ** 0.8) * s * (1 - 0.85 * t ** 3) + 0.004 * s
        rows.append([ctr + r * np.array([math.cos(2 * math.pi * j / segs), math.sin(2 * math.pi * j / segs), 0])
                     for j in range(segs)])
    tail_cols = [bcol["Tail%d" % i] for i in range(TAIL_BONES)]

    def wfn(pos, nrows, k):
        jn, wg = [], []
        for r in range(nrows):
            f = (r / (nrows - 1)) * TAIL_BONES
            i = min(int(f), TAIL_BONES - 1)
            frac = f - i
            j2 = min(i + 1, TAIL_BONES - 1)
            for _ in range(k):
                if frac < 0.5 or j2 == i:
                    jn.append((tail_cols[i], tail_cols[max(i - 1, 0)], 0, 0))
                    wg.append((0.5 + frac if i > 0 else 1.0, 0.5 - frac if i > 0 else 0.0, 0, 0))
                else:
                    jn.append((tail_cols[i], tail_cols[j2], 0, 0))
                    wg.append((1.5 - frac, frac - 0.5, 0, 0))
        return np.array(jn, np.uint8), np.array(wg, float)
    pos, nrm, uv, col, jnt, wgt, tris = _grid_prim(rows, 0, close=True, weights_fn=wfn)
    nrm, tris = orient(pos, tris, base + np.array([0, 0, -total * 0.5]))
    uv[:, 1] *= 6.0
    part = Part("Tail")
    part.add("fur", pos, nrm, uv, col, jnt, wgt, tris)
    return part, heads


# ----------------------------------------------------------------- glTF writer

def to_godot(p):
    """MakeHuman faces +Z; the game faces -Z. Rotate 180 degrees about Y."""
    p = np.array(p, np.float32)
    p[..., 0] *= -1
    p[..., 2] *= -1
    return p


def write_glb(path, bone_names, heads, parents, parts, meta):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    blob = bytearray()
    views, accessors = [], []

    def add(arr, comp, typ, target=None, minmax=False, normalized=False):
        arr = np.ascontiguousarray(arr)
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(arr.tobytes())
        v = {"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes}
        if target:
            v["target"] = target
        views.append(v)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(x) for x in arr.min(0)]
            acc["max"] = [float(x) for x in arr.max(0)]
        accessors.append(acc)
        return len(accessors) - 1

    nodes = []
    bone_node = {}
    for b in bone_names:
        bone_node[b] = len(nodes)
        nodes.append({"name": b})
    for b in bone_names:
        p = parents[b]
        h = to_godot(heads[b])
        ph = to_godot(heads[p]) if p else np.zeros(3, np.float32)
        nodes[bone_node[b]]["translation"] = [float(x) for x in (h - ph)]
        if p:
            nodes[bone_node[p]].setdefault("children", []).append(bone_node[b])
    ibm = []
    for b in bone_names:
        h = to_godot(heads[b])
        m = np.eye(4, dtype=np.float32)
        m[:3, 3] = -h
        ibm.append(m.T.reshape(-1))
    ibm_acc = add(np.array(ibm, np.float32), 5126, "MAT4")
    skin = {"joints": [bone_node[b] for b in bone_names], "inverseBindMatrices": ibm_acc, "skeleton": bone_node["Hips"]}

    materials, mat_index, meshes = [], {}, []
    for part in parts:
        prims = []
        for material, pos, nrm, uv, col, jnt, wgt, tris in part.prims:
            if material not in mat_index:
                mat_index[material] = len(materials)
                materials.append({"name": material, "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.8, 0.8, 1],
                                                                            "metallicFactor": 0.0, "roughnessFactor": 0.8},
                                  "doubleSided": material in ("fin", "cloak")})
            tris = np.asarray(tris, np.uint32)
            # Godot (and glTF) expect counter-clockwise fronts; MakeHuman winding survives the 180 degree turn.
            idx_type = 5123 if len(pos) < 65535 else 5125
            idx = tris.reshape(-1).astype(np.uint16 if idx_type == 5123 else np.uint32)
            prim = {"attributes": {
                "POSITION": add(to_godot(pos), 5126, "VEC3", 34962, minmax=True),
                "NORMAL": add(to_godot(nrm), 5126, "VEC3", 34962),
                "TEXCOORD_0": add(np.asarray(uv, np.float32), 5126, "VEC2", 34962),
                "COLOR_0": add(np.clip(np.asarray(col, np.float32), 0, 1), 5126, "VEC4", 34962),
                "JOINTS_0": add(np.asarray(jnt, np.uint8), 5121, "VEC4", 34962),
                "WEIGHTS_0": add(np.asarray(wgt, np.float32), 5126, "VEC4", 34962),
            }, "indices": add(idx, idx_type, "SCALAR", 34963), "material": mat_index[material]}
            prims.append(prim)
        if prims:
            meshes.append({"name": part.name, "primitives": prims})
            nodes.append({"name": part.name, "mesh": len(meshes) - 1, "skin": 0})
    root = {"name": "Character", "children": [bone_node["Hips"]] + list(range(len(bone_names), len(nodes))),
            "extras": meta}
    nodes.append(root)
    gltf = {"asset": {"version": "2.0", "generator": "Velicia build_characters.py (MakeHuman CC0 base)"},
            "scene": 0, "scenes": [{"nodes": [len(nodes) - 1]}], "nodes": nodes, "meshes": meshes,
            "materials": materials, "skins": [skin], "accessors": accessors, "bufferViews": views,
            "buffers": [{"byteLength": len(blob)}]}
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(blob) % 4:
        blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(blob)
    print("wrote %s (%.0f KB, %d meshes)" % (os.path.relpath(path, ROOT), (len(js) + len(blob)) / 1024, len(meshes)))


def main():
    names = sys.argv[1:] or list(CHARACTERS)
    base = load_obj()
    rig = Rig()
    metas = {}
    for name in names:
        metas[name] = build_character(name, CHARACTERS[name], base, rig)
    return metas


if __name__ == "__main__":
    main()
