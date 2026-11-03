#!/usr/bin/env python3
"""Original chiptune music for Velicia (Game Boy-style channels: two pulse
waves, a triangle-ish wave for bass and a noise drum).

    python3 tools/make_music.py      -> audio/music/*.wav

All melodies here are written for this project (no borrowed tunes).
Notes: 'C4', 'D#5' ...; '-' rest; durations in sixteenth notes.
"""
import math
import os
import random
import struct
import wave

RATE = 16000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "music")
NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def freq(note):
    if note == "-":
        return 0.0
    name, octave = note[:-1], int(note[-1])
    n = NAMES[name] + (octave + 1) * 12
    return 440.0 * 2 ** ((n - 69) / 12.0)


def parse(seq):
    """'E5:2 G5:2 -:4' -> [(freq, sixteenths)]"""
    out = []
    for tok in seq.split():
        n, d = tok.split(":") if ":" in tok else (tok, "2")
        out.append((freq(n), int(d)))
    return out


def render(parts, bpm, bars, duty=(0.5, 0.25)):
    """parts: dict lead/harm/bass/drums -> note list (repeated to fill)."""
    six = 60.0 / bpm / 4.0
    total = int(bars * 16 * six * RATE)
    buf = [0.0] * total
    rnd = random.Random(3)

    def voice(notes, kind, vol, dut=0.5):
        if not notes:
            return
        t = 0
        i = 0
        while t < total:
            f, d = notes[i % len(notes)]
            n = int(d * six * RATE)
            if f > 0:
                for k in range(n):
                    if t + k >= total:
                        break
                    ph = (k * f / RATE) % 1.0
                    if kind == "pulse":
                        s = 1.0 if ph < dut else -1.0
                    elif kind == "tri":
                        s = 4.0 * abs(ph - 0.5) - 1.0
                    else:
                        s = 0.0
                    env = min(1.0, k / 60.0) * (0.75 + 0.25 * (1.0 - k / max(n, 1)))
                    if k > n - 80:
                        env *= max(0.0, (n - k) / 80.0)
                    buf[t + k] += s * vol * env
            t += n
            i += 1

    def drums(pattern, vol):
        if not pattern:
            return
        t = 0
        i = 0
        while t < total:
            hit, d = pattern[i % len(pattern)]
            n = int(d * six * RATE)
            if hit != "-":
                length = int(RATE * (0.09 if hit == "k" else 0.04))
                pitch = 0.0
                for k in range(min(length, n)):
                    if t + k >= total:
                        break
                    env = (1.0 - k / length) ** 2
                    if hit == "k":
                        pitch += (90 - 50 * k / length) / RATE
                        s = 1.0 if (pitch % 1.0) < 0.5 else -1.0
                    else:
                        s = rnd.uniform(-1, 1)
                    buf[t + k] += s * vol * env
            t += n
            i += 1

    voice(parts.get("lead"), "pulse", 0.16, duty[0])
    voice(parts.get("harm"), "pulse", 0.08, duty[1])
    voice(parts.get("bass"), "tri", 0.2)
    drums(parts.get("drums"), 0.12)
    return buf


def drum_pat(s):
    out = []
    for tok in s.split():
        h, d = tok.split(":")
        out.append((h, int(d)))
    return out


def write(name, buf):
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 30000)) for s in buf)
        w.writeframes(frames)
    print("wrote", name, "%.1fs" % (len(buf) / RATE))


def main():
    # Town: warm, bouncy, major key.
    write("town", render({
        "lead": parse("E5:2 G5:2 A5:4 G5:2 E5:2 D5:4 C5:2 D5:2 E5:2 G5:2 E5:8 "
                      "F5:2 A5:2 C6:4 B5:2 A5:2 G5:4 E5:2 F5:2 G5:2 E5:2 D5:8 "
                      "E5:2 G5:2 A5:4 G5:2 E5:2 D5:4 C5:2 D5:2 E5:2 D5:2 C5:8 "
                      "A4:2 C5:2 D5:4 E5:2 G5:2 A5:4 G5:2 E5:2 D5:2 E5:2 C5:8"),
        "harm": parse("C5:4 E5:4 C5:4 G4:4 E4:4 G4:4 C5:8 F4:4 A4:4 C5:4 B4:4 G4:4 B4:4 G4:8 "
                      "C5:4 E5:4 C5:4 G4:4 E4:4 G4:4 E4:8 F4:4 A4:4 B4:4 C5:4 G4:4 B4:4 C5:8"),
        "bass": parse("C3:4 G3:4 C3:4 G3:4 A2:4 E3:4 A2:4 E3:4 F2:4 C3:4 F2:4 C3:4 G2:4 D3:4 G2:4 D3:4"),
        "drums": drum_pat("k:4 h:4 k:4 h:2 h:2"),
    }, 112, 16))
    # Route: adventurous, driving.
    write("route", render({
        "lead": parse("D5:2 -:2 D5:2 E5:2 F#5:4 A5:4 G5:2 F#5:2 E5:2 D5:2 E5:8 "
                      "D5:2 -:2 D5:2 E5:2 F#5:4 A5:4 B5:4 A5:2 G5:2 F#5:8 "
                      "G5:2 -:2 G5:2 A5:2 B5:4 D6:4 C#6:2 B5:2 A5:2 G5:2 A5:8 "
                      "F#5:2 G5:2 A5:2 F#5:2 E5:4 D5:4 E5:2 F#5:2 E5:2 C#5:2 D5:8"),
        "harm": parse("A4:8 D5:8 B4:8 C#5:8 A4:8 D5:8 G4:8 A4:8 B4:8 D5:8 A4:8 C#5:8 D5:8 B4:8 A4:8 F#4:8"),
        "bass": parse("D3:2 D3:2 A2:2 D3:2 D3:2 D3:2 A2:2 D3:2 G2:2 G2:2 D3:2 G2:2 A2:2 A2:2 E3:2 A2:2"),
        "drums": drum_pat("k:2 h:2 h:2 k:2 k:2 h:2 h:2 h:2"),
    }, 132, 16))
    # Battle: urgent minor key, fast.
    write("battle", render({
        "lead": parse("A4:1 C5:1 E5:1 A5:1 G5:2 E5:2 F5:2 D5:2 E5:4 A4:1 C5:1 E5:1 A5:1 B5:2 G5:2 A5:4 E5:4 "
                      "F5:2 F5:1 G5:1 A5:2 F5:2 E5:2 E5:1 F5:1 G5:2 E5:2 D5:2 D5:1 E5:1 F5:2 D5:2 E5:8 "
                      "C6:2 B5:2 A5:2 G5:2 A5:2 E5:2 C5:2 E5:2 D5:2 F5:2 A5:2 D6:2 B5:4 G#5:4 "
                      "A5:2 E5:2 C5:2 E5:2 F5:2 E5:2 D5:2 B4:2 C5:2 B4:2 A4:2 G#4:2 A4:8"),
        "harm": parse("E4:2 A4:2 E4:2 A4:2 D4:2 F4:2 E4:2 G#4:2"),
        "bass": parse("A2:1 A3:1 A2:1 A3:1 A2:1 A3:1 A2:1 A3:1 F2:1 F3:1 F2:1 F3:1 E2:1 E3:1 E2:1 E3:1"),
        "drums": drum_pat("k:2 h:1 h:1 s:2 h:1 k:1 k:2 h:1 h:1 s:2 h:2"),
    }, 150, 16, duty=(0.25, 0.5)))
    # Victory fanfare (short, loops politely).
    write("victory", render({
        "lead": parse("G5:2 G5:2 G5:2 G5:6 D#5:6 F5:6 G5:3 F5:1 G5:12 -:8 "
                      "C5:2 E5:2 G5:2 C6:4 B5:2 A5:2 G5:2 E5:2 G5:8 -:4"),
        "bass": parse("C3:4 C3:4 G2:4 G2:4 A#2:4 A#2:4 C3:12 -:8 C3:4 G2:4 F2:4 G2:4 C3:8 -:4"),
        "drums": drum_pat("k:4 h:4"),
    }, 140, 8))
    # Title: stately theme of the Guild.
    write("title", render({
        "lead": parse("C5:4 G5:4 E5:2 F5:2 G5:4 A5:4 G5:2 F5:2 E5:4 D5:4 E5:2 F5:2 G5:8 "
                      "A5:4 F5:4 C6:4 B5:2 A5:2 G5:4 E5:4 D5:4 F5:2 E5:2 C5:8"),
        "harm": parse("E4:8 C5:8 F4:8 E4:8 F4:8 A4:8 G4:8 E4:8"),
        "bass": parse("C3:8 E3:8 F2:8 G2:8 F2:8 A2:8 G2:8 C3:8"),
        "drums": drum_pat("k:8 h:8"),
    }, 96, 16))
    # Gyria camp: tense, low drums.
    write("camp", render({
        "lead": parse("D5:6 F5:2 E5:4 C5:4 D5:8 -:8 A4:6 C5:2 A#4:4 G4:4 A4:8 -:8"),
        "bass": parse("D2:2 -:2 D2:2 D3:2 -:2 D2:2 A2:2 -:2 A#1:2 -:2 A#1:2 A#2:2 -:2 A2:2 A2:4"),
        "drums": drum_pat("k:2 -:2 k:2 h:2 k:4 s:4"),
    }, 104, 16))


if __name__ == "__main__":
    main()
