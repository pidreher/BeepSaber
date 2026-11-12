# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy"]
# ///
"""Synthesizes the game's sound effects (original sounds, no samples used).

    uv run tools/make_sfx.py

Writes 16-bit mono WAVs to game/data/sfx/.
"""
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 48000
OUT = Path(__file__).resolve().parent.parent / "game" / "data" / "sfx"
rng = np.random.default_rng(1234)


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(SR * seconds)) / SR


def band(x: np.ndarray, lo: float | None, hi: float | None, order: int = 4) -> np.ndarray:
    if lo and hi:
        sos = butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    elif lo:
        sos = butter(order, lo, btype="highpass", fs=SR, output="sos")
    else:
        sos = butter(order, hi, btype="lowpass", fs=SR, output="sos")
    return sosfilt(sos, x)


def glide_sine(f: np.ndarray) -> np.ndarray:
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def finish(x: np.ndarray, drive: float = 1.4, peak: float = 0.95, fade: float = 0.01) -> np.ndarray:
    x = np.tanh(drive * x) / np.tanh(drive)
    n = int(SR * fade)
    x[-n:] *= np.linspace(1, 0, n)
    return x / np.max(np.abs(x)) * peak


def save(name: str, x: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    wavfile.write(OUT / name, SR, (x * 32767).astype(np.int16))
    print(f"{name}: {len(x) / SR:.2f}s")


def hit() -> np.ndarray:
    """Cube cut: transient click + punchy low thump + 'tshk' slice + metallic shimmer."""
    t = t_axis(0.38)
    click = band(rng.standard_normal(t.size), 2500, None) * np.exp(-t / 0.0015)
    thump = glide_sine(55 + 150 * np.exp(-t / 0.018)) * np.exp(-t / 0.075)
    slice_env = (1 - np.exp(-t / 0.002)) * np.exp(-t / 0.055)
    slice_ = band(rng.standard_normal(t.size), 2200, 10000) * slice_env
    shimmer = sum(
        a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi)) * np.exp(-t / d)
        for f, a, d in [(1870, 0.10, 0.14), (2950, 0.08, 0.11), (4310, 0.06, 0.09), (6020, 0.04, 0.07)]
    )
    return finish(0.55 * click + 1.0 * thump + 0.55 * slice_ + shimmer)


def fail() -> np.ndarray:
    """Failing a song: impact, then a descending power-down sweep fading into rumble."""
    t = t_axis(2.2)
    f = 35 + 190 * np.exp(-t / 0.55)
    phase = np.cumsum(f) / SR
    saw = 2 * (phase % 1.0) - 1
    square = np.sign(np.sin(2 * np.pi * phase * 1.004))  # slight detune for width
    tone = 0.6 * saw + 0.4 * square
    # time-varying one-pole lowpass closing from ~3 kHz to ~120 Hz
    cutoff = 120 + 2900 * np.exp(-t / 0.45)
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(tone)
    acc = 0.0
    for i in range(tone.size):
        acc = (1 - a[i]) * tone[i] + a[i] * acc
        y[i] = acc
    env = (1 - np.exp(-t / 0.004)) * np.clip((2.2 - t) / 0.9, 0, 1)
    rumble = band(rng.standard_normal(t.size), None, 180) * np.exp(-t / 0.7) * 1.4
    impact = glide_sine(45 + 120 * np.exp(-t / 0.03)) * np.exp(-t / 0.18)
    crash = band(rng.standard_normal(t.size), 800, 7000) * np.exp(-t / 0.08)
    dry = 0.7 * y * env + 0.5 * rumble + 1.5 * impact + 0.6 * crash
    # short noise reverb for some space
    ir_t = t_axis(0.7)
    ir = rng.standard_normal(ir_t.size) * np.exp(-ir_t / 0.18)
    wet = np.convolve(dry, ir)[: dry.size]
    wet = wet / np.max(np.abs(wet)) * np.max(np.abs(dry))
    return finish(dry + 0.3 * wet, drive=1.2, fade=0.05)


if __name__ == "__main__":
    save("hit.wav", hit())
    save("fail.wav", fail())
