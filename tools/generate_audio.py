#!/usr/bin/env python3
"""Synthesises Velicia's placeholder sound effects, ambience and music.

All output is original, procedurally generated audio (no samples), released
with the project. Replace any file in audio/ with final assets later; the
sound ids in scripts/autoload/audio_manager.gd stay the same.

Usage:  python3 tools/generate_audio.py   (needs numpy)
"""
import os
import wave

import numpy as np

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack=0.01, release=0.2, sustain_level=1.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    total = n / SR
    r = np.clip((total - t) / max(release, 1e-4), 0, 1)
    return a * r * sustain_level


def decay(n, rate):
    return np.exp(-np.arange(n) / SR * rate)


def lowpass(x, cutoff):
    # One-pole low-pass; cutoff may be an array for sweeps.
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    y = np.zeros_like(x)
    acc = 0.0
    k = 1.0 - np.exp(-2 * np.pi * cutoff / SR)
    for i in range(len(x)):
        acc += k[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def noise(seconds):
    return rng.uniform(-1, 1, int(SR * seconds))


def tone(freq, seconds, kind="sine"):
    t = t_axis(seconds)
    freq = np.broadcast_to(np.asarray(freq, dtype=float), t.shape)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    if kind == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    if kind == "tri":
        return 2 * np.abs(2 * ((phase / (2 * np.pi)) % 1.0) - 1) - 1
    return np.sin(phase)


def bell(freq, seconds, rate=6.0):
    n = int(SR * seconds)
    out = np.zeros(n)
    for ratio, amp in [(1, 1.0), (2.01, 0.5), (3.0, 0.25), (4.2, 0.15)]:
        out += amp * tone(freq * ratio, seconds) * decay(n, rate * (1 + ratio * 0.3))
    return out / 1.9


def write(name, x, folder="sfx", gain=0.9):
    x = np.asarray(x, dtype=float)
    peak = np.max(np.abs(x)) or 1.0
    x = np.clip(x / peak * gain, -1, 1)
    path = os.path.join(ROOT, folder, name + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    print("wrote", os.path.relpath(path, ROOT), "%.1fs" % (len(x) / SR))


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def place(buf, x, at):
    i = int(at * SR)
    end = min(len(buf), i + len(x))
    buf[i:end] += x[: end - i]


# ------------------------------------------------------------------ SFX

def sfx():
    n = noise(0.28)
    write("swing", lowpass(n, np.linspace(600, 3800, len(n))) * env(len(n), 0.08, 0.15))
    n = noise(0.42)
    write("swing_heavy", lowpass(n, np.linspace(300, 1800, len(n))) * env(len(n), 0.15, 0.2))
    thump = tone(np.linspace(140, 55, int(SR * 0.2)), 0.2) * decay(int(SR * 0.2), 18)
    crack = highpass(noise(0.06), 900) * decay(int(SR * 0.06), 60)
    write("hit", mix(thump, crack * 0.6))
    clang = sum(a * tone(f, 0.4) * decay(int(SR * 0.4), d) for f, a, d in [(820, 1, 9), (1293, 0.7, 11), (2131, 0.5, 14), (3010, 0.3, 18)])
    write("block", mix(clang, highpass(noise(0.03), 2000) * 0.8))
    ring = sum(a * tone(f, 0.8) * decay(int(SR * 0.8), d) for f, a, d in [(1200, 1, 4), (1807, 0.8, 5), (2702, 0.5, 6), (3605, 0.4, 7)])
    write("parry", mix(ring, highpass(noise(0.04), 2500)))
    write("footstep", lowpass(noise(0.09), 500) * decay(int(SR * 0.09), 45), gain=0.6)
    n = noise(0.22)
    write("dodge", lowpass(n, np.linspace(2000, 500, len(n))) * env(len(n), 0.03, 0.15), gain=0.6)
    cap = np.zeros(int(SR * 1.1))
    for i, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        place(cap, bell(f, 0.7), i * 0.11)
    write("ring_capture", cap)
    t = t_axis(0.7)
    shimmer = tone(np.linspace(300, 1200, len(t)), 0.7, "tri") * env(len(t), 0.05, 0.4)
    shimmer += 0.4 * tone(np.linspace(600, 2400, len(t)), 0.7) * env(len(t), 0.1, 0.4)
    write("ring_summon", shimmer)
    fail = np.zeros(int(SR * 0.6))
    for i, f in enumerate([659.25, 523.25, 392.0]):
        place(fail, bell(f, 0.35, 10), i * 0.1)
    write("ring_fail", fail)
    t = t_axis(0.35)
    horn = (tone(220, 0.35, "saw") * 0.5 + tone(330, 0.35, "saw") * 0.3)
    write("alert", lowpass(horn, 1200) * env(len(t), 0.02, 0.15), gain=0.7)
    t = t_axis(1.3)
    growl = tone(70 + 8 * np.sin(2 * np.pi * 6 * t), 1.3, "saw") * (0.6 + 0.4 * np.sin(2 * np.pi * 11 * t))
    growl = lowpass(growl, 600) + lowpass(noise(1.3), 900) * 0.5
    write("roar", growl * env(len(t), 0.15, 0.5))
    pick = np.zeros(int(SR * 0.3))
    place(pick, bell(1318.5, 0.2, 14), 0.0)
    place(pick, bell(1760, 0.25, 12), 0.07)
    write("pickup", pick, gain=0.6)
    write("ui_click", highpass(noise(0.03), 1500) * decay(int(SR * 0.03), 120), gain=0.4)
    lv = np.zeros(int(SR * 1.2))
    for i, f in enumerate([392.0, 493.88, 587.33, 783.99, 987.77]):
        place(lv, bell(f, 0.7, 5), i * 0.09)
    write("level_up", lv)
    t = t_axis(0.16)
    write("creature_attack", mix(tone(np.linspace(900, 300, len(t)), 0.16, "tri") * decay(len(t), 20), highpass(noise(0.05), 1200) * 0.5))
    t = t_axis(0.6)
    chord = sum(tone(f * (1 + 0.003 * np.sin(2 * np.pi * 7 * t)), 0.6) for f in [523.25, 659.25, 987.77])
    write("magic", chord * env(len(t), 0.05, 0.35))


# ------------------------------------------------------------- Ambience

def ambience():
    seconds = 12.0
    n = noise(seconds)
    t = t_axis(seconds)
    sweep = 400 + 300 * np.sin(2 * np.pi * t / seconds) + 120 * np.sin(2 * np.pi * 3 * t / seconds)
    wind = lowpass(n, sweep) * (0.55 + 0.45 * np.sin(2 * np.pi * 2 * t / seconds) ** 2)
    write("ambience_wind", wind, gain=0.5)


# ----------------------------------------------------------------- Music

NOTE = {"A2": 110.0, "C3": 130.81, "D3": 146.83, "E3": 164.81, "F3": 174.61, "G3": 196.0,
        "A3": 220.0, "B3": 246.94, "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23,
        "G4": 392.0, "A4": 440.0, "B4": 493.88, "C5": 523.25, "D5": 587.33, "E5": 659.25}


def pad(freqs, seconds):
    t = t_axis(seconds)
    out = np.zeros(len(t))
    for f in freqs:
        for det in (-0.004, 0.0, 0.005):
            out += tone(f * (1 + det), seconds, "tri")
    return lowpass(out, 1400) * env(len(t), 0.6, 0.8)


def pluck(f, seconds=0.6):
    n = int(SR * seconds)
    return (tone(f, seconds, "tri") * 0.7 + tone(f * 2, seconds) * 0.3) * decay(n, 7)


def exploration_music():
    bar = 4.0
    prog = [["A3", "C4", "E4"], ["F3", "A3", "C4"], ["C3", "E3", "G3", "C4"], ["G3", "B3", "D4"]]
    melody = ["E4", "A4", "C5", "B4", "A4", "F4", "A4", "C5", "G4", "C5", "E5", "D5", "B4", "G4", "D5", "B4"]
    total = bar * len(prog) * 2
    buf = np.zeros(int(SR * total) + SR)
    for rep in range(2):
        for i, chord in enumerate(prog):
            start = (rep * len(prog) + i) * bar
            place(buf, pad([NOTE[n] for n in chord], bar + 0.8) * 0.35, start)
            place(buf, tone(NOTE[chord[0]] / 2, bar, "sine") * env(int(SR * bar), 0.3, 0.6) * 0.3, start)
            for k in range(4):
                note = melody[(i * 4 + k + rep * 3) % len(melody)]
                place(buf, pluck(NOTE[note], 0.9) * 0.28, start + k * 1.0 + (0.5 if rep and k % 2 else 0.0))
    buf = buf[: int(SR * total)]
    # Smooth loop seam
    fade = int(SR * 0.4)
    buf[:fade] *= np.linspace(0, 1, fade)
    buf[-fade:] *= np.linspace(1, 0, fade)
    write("exploration", buf, folder="music", gain=0.55)


def combat_music():
    beat = 0.42
    bars = 8
    total = beat * 4 * bars
    buf = np.zeros(int(SR * total) + SR)
    kick = tone(np.linspace(120, 45, int(SR * 0.25)), 0.25) * decay(int(SR * 0.25), 14)
    tom = tone(np.linspace(200, 120, int(SR * 0.2)), 0.2) * decay(int(SR * 0.2), 16)
    hat = highpass(noise(0.05), 3000) * decay(int(SR * 0.05), 70)
    roots = ["A2", "A2", "F3", "G3", "A2", "A2", "C3", "E3"]
    ost = ["A3", "C4", "E4", "C4", "A3", "E4", "D4", "C4"]
    for b in range(bars):
        start = b * beat * 4
        root = NOTE[roots[b]]
        drone = lowpass(tone(root, beat * 4, "saw") * 0.5 + tone(root * 1.5, beat * 4, "saw") * 0.25, 700)
        place(buf, drone * env(len(drone), 0.05, 0.1) * 0.35, start)
        for k in range(8):
            t0 = start + k * beat / 2
            place(buf, hat * 0.25, t0)
            note = NOTE[ost[(k + b) % len(ost)]] * (2 if roots[b] in ("F3", "G3") else 1)
            place(buf, lowpass(tone(note, 0.18, "saw"), 1800) * decay(int(SR * 0.18), 12) * 0.18, t0)
        for k in (0, 2):
            place(buf, kick * 0.9, start + k * beat)
        place(buf, tom * 0.6, start + 3 * beat)
        place(buf, tom * 0.5, start + 3.5 * beat)
    buf = buf[: int(SR * total)]
    write("combat", buf, folder="music", gain=0.6)


if __name__ == "__main__":
    sfx()
    ambience()
    exploration_music()
    combat_music()
