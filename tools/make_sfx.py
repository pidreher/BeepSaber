# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "scipy"]
# ///
"""Synthesizes the game's sound effects (original sounds, no samples used).

    uv run tools/make_sfx.py
    uv run tools/make_sfx.py --only arc_loop clash_loop cut

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


def cut() -> np.ndarray:
    """Cube cut: a bright crack, then a heavy ~75 Hz thump that rumbles on for about
    half a second, with a faint 1-3 kHz shimmer in the tail."""
    t = t_axis(0.9)
    # crack: ~25 ms of bright noise plus a short click, ahead of the thump
    crack = band(rng.standard_normal(t.size), 3000, 15000) * np.exp(-t / 0.01)
    crack += 0.8 * band(rng.standard_normal(t.size), 500, 3000) * np.exp(-t / 0.004)
    # thump: swells in over ~10 ms, settles from ~95 Hz to ~72 Hz and dies within ~0.4 s
    attack = 1 - np.exp(-t / 0.008)
    thump = glide_sine(72 + 23 * np.exp(-t / 0.035)) * attack * np.exp(-t / 0.13)
    # its overtone gives the impact some 120-250 Hz punch
    overtone = glide_sine(150 + 40 * np.exp(-t / 0.03)) * attack * np.exp(-t / 0.05)
    # rumble: rough low noise with a fast random wobble, so the tail is not a clean tone
    wobble = 1 + 2.7 * band(rng.standard_normal(t.size), None, 30, order=2)
    rumble = band(rng.standard_normal(t.size), 40, 140) * attack * np.exp(-t / 0.14) * wobble
    # sub: a slower 45 Hz layer under the end of the tail
    sub = np.sin(2 * np.pi * 45 * t) * attack * np.exp(-t / 0.22)
    # shimmer: band noise around 1-3 kHz that lingers after the thump
    shimmer = band(rng.standard_normal(t.size), 800, 3500) * (1 - np.exp(-t / 0.06)) * np.exp(-t / 0.28)
    x = 1.0 * thump + 0.35 * overtone + 0.5 * rumble + 0.3 * sub + 1.4 * crack + 0.22 * shimmer
    # gentle saturation thickens the impact
    return finish(x, drive=2.0, fade=0.05)


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
    # deep: 55 Hz fundamental over a 40 Hz sub, soft overtones, little fizz
    # (whole-number frequencies keep the 1 s loop seamless)
    bass = np.sin(2 * np.pi * 55 * t) + 0.6 * np.sin(2 * np.pi * 40 * t)
    body = 0.28 * np.sin(2 * np.pi * 110 * t) + 0.12 * np.sin(2 * np.pi * 165 * t)
    fizz = periodic_noise(1.0, 500, 1800, 9021) * (0.75 + 0.25 * np.sin(2 * np.pi * 5 * t))
    x = np.tanh(1.3 * (bass + body)) + 0.12 * fizz
    return x / np.max(np.abs(x)) * 0.8


def clash_loop() -> np.ndarray:
    """Welding sizzle while two blades stay pressed together: band-limited hiss,
    random crackle bursts and a little mains-like hum. Loops seamlessly."""
    seconds = 2.0
    n = int(SR * seconds)
    t = np.arange(n) / SR
    loop_rng = np.random.default_rng(9022)
    hiss = periodic_noise(seconds, 1800, 7500, 9024)
    # crackle: many tiny bursts of wide-band noise with random times and sizes.
    # Bursts near the end wrap to the start, so the loop point is invisible.
    grains = np.zeros(n)
    noise = periodic_noise(seconds, 700, 9000, 9025)
    for start in loop_rng.integers(0, n, 260):
        length = int(SR * loop_rng.uniform(0.0015, 0.012))
        amp = loop_rng.uniform(0.2, 1.0) ** 2
        idx = (start + np.arange(length)) % n
        grains[idx] += amp * np.exp(-np.arange(length) / (length * 0.3))
    crackle = noise * grains
    # hum: 60 Hz with its 2nd harmonic, slightly rough (no clean tones)
    hum = (np.sin(2 * np.pi * 60 * t) + 0.5 * np.sin(2 * np.pi * 120 * t)) * (0.8 + 0.2 * np.abs(hiss))
    x = 0.35 * hiss + 0.9 * crackle + 0.18 * hum
    x = np.tanh(1.3 * x)
    return x / np.max(np.abs(x)) * 0.75


def bad_cut() -> np.ndarray:
    """Wrong-saber cut: a short dull thud and a harsh, beating buzz around 1-2 kHz,
    clearly different from the bright crack and deep thump of a good cut."""
    t = t_axis(0.45)
    attack = 1 - np.exp(-t / 0.004)
    # two detuned square-ish tones beat against each other
    tones = sum(np.tanh(3 * np.sin(2 * np.pi * f * t)) for f in (1010.0, 1072.0, 1490.0))
    buzz = band(tones, 700, 2600) * attack * np.exp(-t / 0.12)
    thud = np.sin(2 * np.pi * 55 * t) * attack * np.exp(-t / 0.05)
    x = 0.55 * buzz + 0.6 * thud
    return finish(x, drive=1.6, fade=0.04)


def miss() -> np.ndarray:
    """Missed note passing by: a soft, falling low whiff."""
    t = t_axis(0.35)
    attack = 1 - np.exp(-t / 0.02)
    tone = glide_sine(110 + 190 * np.exp(-t / 0.08)) * attack * np.exp(-t / 0.11)
    air = band(rng.standard_normal(t.size), 300, 1500) * attack * np.exp(-t / 0.06)
    x = 0.8 * tone + 0.25 * air
    return finish(x, drive=1.2, fade=0.05)


if __name__ == "__main__":
    generators = dict(hit=hit, cut=cut, bad_cut=bad_cut, miss=miss, fail=fail, arc_loop=arc_loop,
                      clash_loop=clash_loop)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="+", choices=generators)
    args = parser.parse_args()
    for name, generate in generators.items():
        if args.only is None or name in args.only:
            save(name + ".wav", generate())
