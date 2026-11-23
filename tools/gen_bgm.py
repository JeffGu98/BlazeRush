#!/usr/bin/env python3
"""Generate a short original fire/action BGM loop for 烈焰突袭."""
from __future__ import annotations

import math
import struct
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
BPM = 132.0
BARS = 8
BEATS_PER_BAR = 4
BEATS = BARS * BEATS_PER_BAR
SECONDS = BEATS * 60.0 / BPM
N = int(round(SECONDS * SR))
# Nudge to exact loop length in samples
SECONDS = N / SR


def time_axis() -> np.ndarray:
    return np.arange(N, dtype=np.float64) / SR


def midi_hz(m: float) -> float:
    return 440.0 * (2.0 ** ((m - 69.0) / 12.0))


def adsr(n: int, a: float, d: float, s: float, r: float, peak: float = 1.0) -> np.ndarray:
    env = np.zeros(n, dtype=np.float64)
    ia, id_, ir = int(a * SR), int(d * SR), int(r * SR)
    ia = max(1, ia)
    ir = max(1, ir)
    isus = n - ia - id_ - ir
    if isus < 0:
        # shrink release/decay
        ir = max(1, n // 4)
        ia = max(1, min(ia, n // 6))
        id_ = max(0, n - ia - ir)
        isus = 0
    i = 0
    env[i : i + ia] = np.linspace(0.0, peak, ia, endpoint=False)
    i += ia
    if id_ > 0:
        env[i : i + id_] = np.linspace(peak, peak * s, id_, endpoint=False)
        i += id_
    if isus > 0:
        env[i : i + isus] = peak * s
        i += isus
    env[i : i + ir] = np.linspace(env[i - 1] if i else peak * s, 0.0, min(ir, n - i), endpoint=True)
    if n - (i + ir) > 0:
        env[i + ir :] = 0.0
    return env[:n]


def one_pole_lp(x: np.ndarray, cutoff: float) -> np.ndarray:
    rc = 1.0 / (2.0 * math.pi * max(20.0, cutoff))
    a = 1.0 / (rc * SR + 1.0)
    try:
        from scipy.signal import lfilter
        return lfilter([a], [1.0, a - 1.0], x)
    except Exception:
        y = np.empty_like(x)
        acc = 0.0
        xv = x
        for i in range(x.shape[0]):
            acc += a * (xv[i] - acc)
            y[i] = acc
        return y


def one_pole_hp(x: np.ndarray, cutoff: float) -> np.ndarray:
    return x - one_pole_lp(x, cutoff)


def soft(x: np.ndarray, g: float = 1.0) -> np.ndarray:
    return np.tanh(x * g)


def saw(t: np.ndarray, freq: np.ndarray | float, phase: float = 0.0) -> np.ndarray:
    return 2.0 * np.mod(t * freq + phase, 1.0) - 1.0


def square(t: np.ndarray, freq: np.ndarray | float, phase: float = 0.0) -> np.ndarray:
    return np.sign(np.sin(2.0 * np.pi * t * freq + phase) + 1e-9)


def sine(t: np.ndarray, freq: np.ndarray | float, phase: float = 0.0) -> np.ndarray:
    return np.sin(2.0 * np.pi * t * freq + phase)


def noise(n: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return rng.uniform(-1.0, 1.0, n)


def place(buf: np.ndarray, start: int, sig: np.ndarray, gain: float = 1.0) -> None:
    if start >= len(buf) or start < 0:
        return
    end = min(len(buf), start + len(sig))
    buf[start:end] += sig[: end - start] * gain


def beat_sample(beat: float) -> int:
    return int(round(beat * 60.0 / BPM * SR)) % N


def main() -> int:
    t = time_axis()
    left = np.zeros(N, dtype=np.float64)
    right = np.zeros(N, dtype=np.float64)

    beat_len = 60.0 / BPM
    sixteenth = beat_len / 4.0

    # ---- Kick (mid-punchy for phone speakers) ----
    for bi in range(BEATS):
        # four-on-the-floor with a light extra on the "and" of 3 every other bar
        hits = [True]
        if bi % 8 == 6:
            # already will add below
            pass
        # main downbeats
        start = beat_sample(bi)
        dur = int(0.22 * SR)
        tt = np.arange(dur) / SR
        freq = 130.0 * np.exp(-tt * 14.0) + 48.0
        body = np.sin(2.0 * np.pi * np.cumsum(freq) / SR)
        click = np.sin(2.0 * np.pi * 1900.0 * tt) * np.exp(-tt * 70.0) * 0.35
        env = np.exp(-tt * 9.5)
        env[: int(0.003 * SR)] *= np.linspace(0, 1, int(0.003 * SR))
        sig = soft((body * env + click) * 1.4, 1.2)
        place(left, start, sig, 0.95)
        place(right, start, sig, 0.95)
        # extra pickup on bars 2,4,6,8 beat 4 "e"
        if bi % 4 == 3 and (bi // 4) % 2 == 1:
            start2 = beat_sample(bi + 0.5)
            dur2 = int(0.14 * SR)
            tt2 = np.arange(dur2) / SR
            freq2 = 150.0 * np.exp(-tt2 * 18.0) + 55.0
            body2 = np.sin(2.0 * np.pi * np.cumsum(freq2) / SR) * np.exp(-tt2 * 14.0)
            place(left, start2, body2, 0.45)
            place(right, start2, body2, 0.45)

    # ---- Snare / clap on 2 and 4 ----
    rng_sn = np.random.default_rng(7)
    for bi in range(BEATS):
        if bi % 4 not in (1, 3):
            continue
        start = beat_sample(bi)
        dur = int(0.28 * SR)
        tt = np.arange(dur) / SR
        nse = rng_sn.uniform(-1.0, 1.0, dur)
        # crude band emphasis
        nse = nse - np.convolve(nse, np.ones(9) / 9.0, mode="same")
        tone = np.sin(2.0 * np.pi * 215.0 * tt) * np.exp(-tt * 18.0)
        env = np.exp(-tt * 16.0)
        env[: max(1, int(0.002 * SR))] = np.linspace(0, 1, max(1, int(0.002 * SR)))
        sig = soft((nse * env * 0.7 + tone * 0.55) * 1.3, 1.1)
        pan = 0.08 if bi % 4 == 1 else -0.08
        place(left, start, sig, 0.72 * (1 - pan))
        place(right, start, sig, 0.72 * (1 + pan))

    # ---- Hats ----
    rng_hat = np.random.default_rng(21)
    for i in range(BEATS * 4):  # 16ths
        start = beat_sample(i / 4.0)
        open_hat = i % 8 == 6
        dur = int((0.09 if not open_hat else 0.18) * SR)
        nse = rng_hat.uniform(-1.0, 1.0, dur)
        # highpass-ish: subtract moving average
        nse = nse - np.convolve(nse, np.ones(5) / 5.0, mode="same")
        tt = np.arange(dur) / SR
        env = np.exp(-tt * (38.0 if not open_hat else 16.0))
        accent = 1.0 if i % 2 == 1 else 0.62
        sig = nse * env * accent
        pan = 0.25 if i % 2 == 0 else -0.2
        g = 0.22 if not open_hat else 0.16
        place(left, start, sig, g * (1 - pan))
        place(right, start, sig, g * (1 + pan))

    # ---- Chord / bass plan, 2 bars each: Dm | Bb | C | A ----
    # roots MIDI: D2=38, Bb1=34, C2=36, A1=33
    roots = []
    for bar, root in enumerate([38, 38, 34, 34, 36, 36, 33, 33]):
        roots.extend([root] * 4)

    # Bass: pumping 8ths
    bass = np.zeros(N, dtype=np.float64)
    for bi in range(BEATS * 2):  # 8th notes
        beat = bi * 0.5
        root = roots[int(beat) % len(roots)]
        # pattern: root, root+12 ghost, fifth, root
        step = bi % 4
        if step == 0:
            note = root
            vel = 1.0
        elif step == 1:
            note = root + 12
            vel = 0.45
        elif step == 2:
            note = root + 7
            vel = 0.82
        else:
            note = root
            vel = 0.55
        start = beat_sample(beat)
        dur = int(0.28 * SR)
        tt = np.arange(dur) / SR
        f = midi_hz(note)
        sig = 0.62 * saw(tt, f) + 0.45 * sine(tt, f) + 0.15 * saw(tt, f * 1.005, 0.3)
        env = adsr(dur, 0.008, 0.06, 0.55, 0.12, peak=vel)
        # light pitch blip at start
        sig = sig * env
        place(bass, start, sig, 0.85)
    # Can't afford slow python one-pole on full buffer if it's a Python loop... 
    # Use a vectorized-ish filter via lfilter if scipy, else numpy loop is ~44100*15 = ok (~0.2s)
    bass = one_pole_lp(bass, 720.0)
    bass = soft(bass, 1.15)
    left += bass * 0.72
    right += bass * 0.72

    # Sidechain ducking envelope from kicks (simple beat-synced)
    duck = np.ones(N, dtype=np.float64)
    for bi in range(BEATS):
        start = beat_sample(bi)
        dlen = int(0.22 * SR)
        end = min(N, start + dlen)
        tt = np.arange(end - start) / SR
        duck[start:end] *= 1.0 - 0.45 * np.exp(-tt * 14.0)
    # Apply light duck to bass already mixed? Apply to a mid layer later. Duck whole mid later.

    # ---- Dark pad (furnace bed) ----
    pad = np.zeros(N, dtype=np.float64)
    chord_tones = {
        38: [38, 41, 45, 50],  # Dm: D F A D
        34: [34, 38, 41, 46],  # Bb: Bb D F Bb
        36: [36, 40, 43, 48],  # C: C E G C  (major, lift)
        33: [33, 36, 40, 45],  # A: A C E A  (minor, tension)
    }
    for bar, root in enumerate([38, 38, 34, 34, 36, 36, 33, 33]):
        start = beat_sample(bar * 4)
        dur = int((4 * beat_len + 0.08) * SR)
        tt = np.arange(dur) / SR
        tones = chord_tones[root]
        sig = np.zeros(dur)
        for k, m in enumerate(tones):
            f = midi_hz(m)
            sig += 0.28 * sine(tt, f, k * 0.2)
            sig += 0.12 * sine(tt, f * 2.002, k * 0.4)
        env = adsr(dur, 0.2, 0.3, 0.75, 0.4)
        # slow tremolo like fire flicker
        flick = 0.85 + 0.15 * np.sin(2.0 * np.pi * 5.5 * tt + bar)
        place(pad, start, sig * env * flick, 0.9)
    pad_l = pad * 0.38
    pad_r = pad * 0.38
    # slight delay for width
    delay = int(0.018 * SR)
    pad_r = np.roll(pad_r, delay)
    left += pad_l
    right += pad_r

    # ---- Ember noise texture ----
    ember = noise(N, 99)
    ember = one_pole_lp(ember, 1200.0)
    ember = one_pole_hp(ember, 200.0)
    flicker = 0.5 + 0.5 * (0.5 * np.sin(2 * np.pi * 3.1 * t) + 0.5 * np.sin(2 * np.pi * 7.7 * t + 1.2))
    ember *= flicker * 0.08
    left += ember
    right += ember * 0.92 + np.roll(ember, 73) * 0.08

    # ---- Ostinato arpeggio (fire motif) ----
    # 16th arpeggios following chord: 1 5 8 12 8 5 8 5 pattern in current chord
    arp = np.zeros(N, dtype=np.float64)
    arp_r = np.zeros(N, dtype=np.float64)
    for i in range(BEATS * 4):
        beat = i / 4.0
        root = roots[int(beat) % len(roots)]
        # scale degrees relative to root: 0, 7, 12, 16 (3rd an octave up), 12, 7, 10, 7
        degrees = [0, 7, 12, 16, 12, 7, 10, 7]
        note = root + 12 + degrees[i % 8]  # around D3+
        start = beat_sample(beat)
        dur = int(0.14 * SR)
        tt = np.arange(dur) / SR
        f = midi_hz(note)
        sig = 0.55 * saw(tt, f) + 0.25 * square(tt, f * 0.5) + 0.2 * sine(tt, f * 2)
        env = adsr(dur, 0.004, 0.04, 0.25, 0.08, peak=0.85 if i % 2 == 0 else 0.6)
        sig *= env
        # skip some 16ths in bars 1-2 to leave space, fuller later
        bar = int(beat // 4)
        if bar < 2 and i % 4 == 3:
            continue
        pan = -0.35 if i % 2 == 0 else 0.4
        place(arp, start, sig, 0.28 * (1 - pan))
        place(arp_r, start, sig, 0.28 * (1 + pan))
    arp = one_pole_lp(arp, 3200.0)
    arp_r = one_pole_lp(arp_r, 3200.0)
    left += arp
    right += arp_r

    # ---- Lead hook (bars 3-8, answers the rhythm) ----
    # Phrase (eighths): D4 F4 G4 A4  G4 F4 E4 D4 | F4 A4 C5 A4  G4 F4 E4 C4
    # MIDI D4=62, F4=65, G4=67, A4=69, E4=64, C5=72, C4=60
    hook_a = [62, 65, 67, 69, 67, 65, 64, 62]
    hook_b = [65, 69, 72, 69, 67, 65, 64, 60]
    hook_c = [62, 62, 65, 67, 69, 67, 65, 62]
    hook_d = [64, 65, 67, 69, 72, 69, 67, 64]
    phrases = {
        2: hook_a,
        3: hook_b,
        4: hook_c,
        5: hook_a,
        6: hook_d,
        7: hook_b,
    }
    lead_l = np.zeros(N)
    lead_r = np.zeros(N)
    for bar, phrase in phrases.items():
        for k, note in enumerate(phrase):
            start = beat_sample(bar * 4 + k * 0.5)
            dur = int(0.36 * SR)
            tt = np.arange(dur) / SR
            f = midi_hz(note)
            # slightly "burning" saw + fifth
            sig = 0.6 * saw(tt, f) + 0.2 * saw(tt, f * 1.003, 0.2) + 0.2 * sine(tt, f * 2)
            env = adsr(dur, 0.01, 0.08, 0.45, 0.16)
            vibr = 1.0 + 0.004 * np.sin(2 * np.pi * 5.5 * tt)
            sig = (0.6 * saw(tt, f * vibr) + 0.2 * saw(tt, f * 1.003, 0.2) + 0.2 * sine(tt, f * 2)) * env
            pan = -0.15 + 0.3 * math.sin(k)
            place(lead_l, start, sig, 0.42 * (1 - pan))
            place(lead_r, start, sig, 0.42 * (1 + pan))
    left += lead_l
    right += lead_r

    # ---- Whoosh at the loop seam (wraps) so the join feels intentional ----
    whoosh = noise(int(0.6 * SR), 3)
    whoosh = one_pole_lp(whoosh, 1800.0)
    wt = np.arange(len(whoosh)) / SR
    wenv = np.sin(np.pi * wt / wt[-1]) ** 2
    whoosh *= wenv * 0.18
    # center at end, wrap the tail
    center = N - int(0.15 * SR)
    place(left, center, whoosh, 0.8)
    place(right, center, whoosh, 0.8)
    overflow = center + len(whoosh) - N
    if overflow > 0:
        left[:overflow] += whoosh[-overflow:] * 0.8
        right[:overflow] += whoosh[-overflow:] * 0.8

    # Apply mid duck to everything except we'll just duck a copy... already mixed.
    # Light overall pump so it feels driving
    left *= 0.65 + 0.35 * duck
    right *= 0.65 + 0.35 * duck

    # Stereo pair, DC remove, soft clip, normalize
    left -= left.mean()
    right -= right.mean()
    mix = np.stack([left, right], axis=1)
    mix = soft(mix, 1.05)
    peak = np.max(np.abs(mix))
    if peak < 1e-6:
        raise SystemExit("silent mix")
    # target -1.2 dBTP
    mix *= (10 ** (-1.2 / 20.0)) / peak
    rms = np.sqrt(np.mean(mix ** 2))
    print(f"length={SECONDS:.3f}s samples={N} peak={mix.max():.3f} rms={rms:.3f} ({20*np.log10(rms):.1f} dBFS)")

    out_dir = Path(__file__).resolve().parents[1] / "assets" / "music"
    out_dir.mkdir(parents=True, exist_ok=True)
    wav_path = out_dir / "blaze_theme.wav"
    ogg_path = out_dir / "blaze_theme.ogg"

    pcm = np.clip(mix, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype(np.int16)
    with wave.open(str(wav_path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm16.tobytes())

    cmd = [
        "ffmpeg", "-y", "-i", str(wav_path),
        "-c:a", "libvorbis", "-q:a", "5",
        str(ogg_path),
    ]
    subprocess.check_call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    # Keep ogg as the shipped asset; drop the bulky wav
    wav_path.unlink()
    print(f"wrote {ogg_path} ({ogg_path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
