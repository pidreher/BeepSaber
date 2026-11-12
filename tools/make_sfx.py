# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy"]
# ///
"""Synthesizes the game's sound effects (original sounds, no samples used).

    uv run tools/make_sfx.py
    uv run tools/make_sfx.py --only arc_loop clash_loop saber_clash

Writes 16-bit mono WAVs to game/data/sfx/.
"""
from pathlib import Path
import argparse

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
    """Cube cut: a dull clap + stomp on impact, then a short electric zap for the slice."""
    t = t_axis(0.32)
    # stomp: low thump gliding down
    stomp = glide_sine(50 + 90 * np.exp(-t / 0.02)) * np.exp(-t / 0.085)
    # clap: band-passed noise with a few quick micro-bursts like a real hand clap
    clap_env = sum(np.exp(-np.clip(t - d, 0, None) / 0.004) * (t >= d) * a
                   for d, a in [(0.0, 1.0), (0.007, 0.8), (0.015, 0.6)])
    clap_env = clap_env + 0.35 * np.exp(-t / 0.045)
    clap = band(rng.standard_normal(t.size), 800, 2600) * clap_env
    # zap: buzzy descending saw sweep with a little FM wobble, starting right after the hit
    zt = np.clip(t - 0.035, 0, None)
    f = 420 + 1300 * np.exp(-zt / 0.045)
    f = f * (1 + 0.08 * np.sin(2 * np.pi * 70 * zt))
    phase = np.cumsum(f) / SR
    saw = 2 * (phase % 1.0) - 1
    zap_env = (t >= 0.035) * (1 - np.exp(-zt / 0.004)) * np.exp(-zt / 0.06)
    crackle = band(rng.standard_normal(t.size), 1500, 5000) * zap_env * 0.25
    zap = band(saw, None, 3200) * zap_env + crackle
    x = 1.1 * stomp + 0.8 * clap + 0.45 * zap
    x = band(x, None, 6500, order=2)  # keep it dull rather than crisp
    return finish(x, drive=1.6)


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


def periodic_noise(seconds: float, lo: float, hi: float, seed: int) -> np.ndarray:
    """Band-limited noise with a seamless loop boundary."""
    n = int(SR * seconds)
    frequencies = np.fft.rfftfreq(n, 1 / SR)
    spectrum = np.zeros(frequencies.size, dtype=complex)
    selected = (frequencies >= lo) & (frequencies <= hi)
    phases = np.random.default_rng(seed).uniform(0, 2 * np.pi, selected.sum())
    spectrum[selected] = np.exp(1j * phases)
    x = np.fft.irfft(spectrum, n)
    return x / np.max(np.abs(x))


def arc_loop() -> np.ndarray:
    """Deep electrical flow. The game applies the shared haptic pulse envelope."""
    t = t_axis(1.0)
    bass = np.sin(2 * np.pi * 85 * t)
    body = 0.32 * np.sin(2 * np.pi * 170 * t) + 0.15 * np.sin(2 * np.pi * 255 * t)
    fizz = periodic_noise(1.0, 650, 2400, 9021) * (0.75 + 0.25 * np.sin(2 * np.pi * 5 * t))
    x = bass + body + 0.24 * fizz
    return x / np.max(np.abs(x)) * 0.8


def clash_loop() -> np.ndarray:
    """A restrained crackling sizzle while two blades remain pressed together."""
    t = t_axis(1.0)
    crackle = periodic_noise(1.0, 900, 4200, 9022)
    buzz = np.sin(2 * np.pi * 110 * t + 0.45 * np.sin(2 * np.pi * 55 * t))
    x = 0.48 * buzz + 0.5 * crackle * (0.7 + 0.3 * np.sin(2 * np.pi * 13 * t))
    return x / np.max(np.abs(x)) * 0.75


def saber_clash() -> np.ndarray:
    """A short electrical crack, weighty impact and dying resonant zing."""
    t = t_axis(0.46)
    noise = np.random.default_rng(9023).standard_normal(t.size)
    crack = band(noise, 1800, 6500) * np.exp(-t / 0.018)
    thump = glide_sine(60 + 110 * np.exp(-t / 0.018)) * np.exp(-t / 0.065)
    ring = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t / d)
               for f, a, d in [(280, 0.34, 0.12), (730, 0.24, 0.09), (1230, 0.12, 0.065)])
    zap = glide_sine(210 + 1400 * np.exp(-t / 0.032)) * np.exp(-t / 0.055)
    x = (1.2 * crack + 0.7 * thump + ring + 0.24 * zap) * (1 - np.exp(-t / 0.0008))
    return finish(x, drive=1.35, fade=0.025)


if __name__ == "__main__":
    generators = dict(hit=hit, fail=fail, arc_loop=arc_loop,
                      clash_loop=clash_loop, saber_clash=saber_clash)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="+", choices=generators)
    args = parser.parse_args()
    for name, generate in generators.items():
        if args.only is None or name in args.only:
            save(name + ".wav", generate())
