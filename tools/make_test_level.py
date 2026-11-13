# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "Pillow"]
# ///
"""Builds a test level that shows every gameplay element: all arrow directions,
dots, bombs, walls (side, crouch, full), arcs, chains and light/ring events.

    uv run tools/make_test_level.py [OUT_DIR]

Writes "OpenSaber Test Level/" (Info.dat, ExpertStandard.dat, song.ogg, cover.png)
into OUT_DIR (default: build/). The song is a 120 BPM click track.
Needs ffmpeg with libvorbis on PATH.
"""
import json, subprocess, sys, tempfile, wave
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

BPM = 120
BEATS = 168
SR = 44100
NAME = "OpenSaber Test Level"

out = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "build") / NAME
out.mkdir(parents=True, exist_ok=True)

# --- audio: click on every beat, accent every bar, a low pad so it is not silent
n = int(SR * BEATS * 60 / BPM)
t = np.arange(n) / SR
x = 0.06 * np.sin(2 * np.pi * 55 * t) * (0.6 + 0.4 * np.sin(2 * np.pi * t / 8))
for beat in range(BEATS):
    s = int(beat * 60 / BPM * SR)
    length = int(0.04 * SR)
    ct = np.arange(length) / SR
    f = 1500 if beat % 4 == 0 else 1000
    x[s:s + length] += (0.6 if beat % 4 == 0 else 0.35) * np.sin(2 * np.pi * f * ct) * np.exp(-ct / 0.012)
x = np.clip(x, -1, 1)
with tempfile.TemporaryDirectory() as tmp:
    wav = Path(tmp) / "song.wav"
    with wave.open(str(wav), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "5",
                    "-f", "ogg", str(out / "song.ogg")], check=True)

# --- cover
img = Image.new("RGB", (256, 256), (18, 20, 34))
d = ImageDraw.Draw(img)
d.rectangle([28, 60, 118, 150], fill=(220, 40, 40)); d.rectangle([138, 60, 228, 150], fill=(40, 90, 230))
d.polygon([(48, 80), (98, 80), (73, 110)], fill="white"); d.ellipse([168, 90, 198, 120], fill="white")
d.text((60, 190), "TEST LEVEL", fill="white")
img.save(out / "cover.png")

# --- map (v3). Lanes x 0-3, rows y 0-2, colour c 0 = left (red side), 1 = right.
# Directions d: 0 up, 1 down, 2 left, 3 right, 4 up-left, 5 up-right, 6 down-left, 7 down-right, 8 dot.
notes, bombs, walls, arcs, chains, events = [], [], [], [], [], []
note = lambda b, x, y, c, d: notes.append({"b": b, "x": x, "y": y, "c": c, "d": d, "a": 0})

# 4-20: alternating down/up swings, then all eight directions for each hand
for i, b in enumerate(range(4, 12)):
    note(b, 1, 0, 0, 1 if i % 2 == 0 else 0)
    note(b, 2, 0, 1, 1 if i % 2 == 0 else 0)
for i, d in enumerate([0, 1, 2, 3, 4, 5, 6, 7]):
    b = 12 + i
    note(b, 0 if d in (2, 4, 6) else 1, 1, 0, d)
    note(b + 0.5, 3 if d in (3, 5, 7) else 2, 1, 1, d)
# 22-30: dots on all rows
for i, (x, y) in enumerate([(0, 0), (1, 1), (2, 2), (3, 1), (0, 2), (1, 0), (2, 1), (3, 2)]):
    note(22 + i, x, y, 0 if x < 2 else 1, 8)
# 32-44: bombs around notes (cut the notes, avoid the bombs)
for i, b in enumerate(range(32, 44, 2)):
    note(b, 1, 0, 0, 1); note(b, 2, 0, 1, 1)
    bombs.append({"b": b, "x": 0, "y": 1}); bombs.append({"b": b, "x": 3, "y": 1})
    bombs.append({"b": b + 1, "x": 1 + i % 2, "y": 2})
# 48-72: walls: left side wall, right side wall, crouch wall, then a full-height centre wall to dodge
walls.append({"b": 48, "x": 0, "y": 0, "d": 4, "w": 1, "h": 5})
note(49, 2, 0, 1, 1); note(51, 3, 0, 1, 1)
walls.append({"b": 54, "x": 3, "y": 0, "d": 4, "w": 1, "h": 5})
note(55, 1, 0, 0, 1); note(57, 0, 0, 0, 1)
walls.append({"b": 60, "x": 0, "y": 2, "d": 3, "w": 4, "h": 3})   # crouch
walls.append({"b": 66, "x": 1, "y": 0, "d": 3, "w": 2, "h": 5})   # step aside
# 76-92: arcs (head note, arc to tail note)
for b, c, hx, tx in [(76, 0, 1, 0), (84, 1, 2, 3)]:
    note(b, hx, 0, c, 0); note(b + 4, tx, 2, c, 1)
    arcs.append({"c": c, "b": b, "x": hx, "y": 0, "d": 0, "mu": 1, "tb": b + 4, "tx": tx, "ty": 2, "tc": 1, "tmu": 1, "m": 0})
# 96-108: chains
for b, c, x0, x1 in [(96, 0, 1, 0), (100, 1, 2, 3), (104, 0, 0, 1), (106, 1, 3, 2)]:
    note(b, x0, 2, c, 1)
    chains.append({"c": c, "b": b, "x": x0, "y": 2, "d": 1, "tb": b + 0.5, "tx": x1, "ty": 0, "sc": 5, "s": 1})
# 112-160: everything mixed, faster
for i, b in enumerate(np.arange(112, 160, 1.0)):
    b = float(b)
    note(b, 1, 0 if i % 3 else 1, 0, 1 if i % 2 == 0 else 0)
    note(b, 2, 0 if i % 3 else 1, 1, 1 if i % 2 == 0 else 0)
    if i % 6 == 3: bombs.append({"b": b + 0.5, "x": 0, "y": 2}); bombs.append({"b": b + 0.5, "x": 3, "y": 2})
    if i % 12 == 6: walls.append({"b": b + 0.5, "x": 0, "y": 0, "d": 1, "w": 1, "h": 5})

# lights: values 1-4 right colour (on, flash, fade, fade-to), 5-8 left, 9-12 white
for b in range(0, BEATS, 1):
    for et in range(5):
        if (b + et) % 4 == 0:
            events.append({"b": b, "et": et, "i": [2, 6, 3, 7, 1, 5][(b // 4 + et) % 6], "f": 1.0})
for b in range(8, BEATS, 2):
    events.append({"b": b, "et": 8, "i": 0, "f": 1.0})            # ring spin
for b in range(16, BEATS, 8):
    events.append({"b": b, "et": 9, "i": 0, "f": 1.0})            # ring zoom
# a fade-to transition: on at 100, fade to white at 104
events += [{"b": 100, "et": 4, "i": 1, "f": 1.0}, {"b": 104, "et": 4, "i": 12, "f": 1.0}]
events.sort(key=lambda e: e["b"])

key = lambda o: o["b"]
level = {"version": "3.2.0", "bpmEvents": [], "rotationEvents": [],
         "colorNotes": sorted(notes, key=key), "bombNotes": sorted(bombs, key=key),
         "obstacles": sorted(walls, key=key), "sliders": arcs, "burstSliders": chains,
         "waypoints": [], "basicBeatmapEvents": events, "colorBoostBeatmapEvents": [],
         "lightColorEventBoxGroups": [], "lightRotationEventBoxGroups": [],
         "lightTranslationEventBoxGroups": [], "basicEventTypesWithKeywords": {}, "useNormalEventsAsCompatibleEvents": True}
(out / "ExpertStandard.dat").write_text(json.dumps(level))

info = {"_version": "2.0.0", "_songName": "Test Level", "_songSubName": "every element",
        "_songAuthorName": "Open Saber", "_levelAuthorName": "Open Saber", "_beatsPerMinute": BPM,
        "_songTimeOffset": 0, "_shuffle": 0, "_shufflePeriod": 0.5, "_previewStartTime": 30,
        "_previewDuration": 10, "_songFilename": "song.ogg", "_coverImageFilename": "cover.png",
        "_environmentName": "DefaultEnvironment", "_allDirectionsEnvironmentName": "GlassDesertEnvironment",
        "_difficultyBeatmapSets": [{"_beatmapCharacteristicName": "Standard", "_difficultyBeatmaps": [
            {"_difficulty": "Expert", "_difficultyRank": 7, "_beatmapFilename": "ExpertStandard.dat",
             "_noteJumpMovementSpeed": 14, "_noteJumpStartBeatOffset": 0}]}]}
(out / "Info.dat").write_text(json.dumps(info, indent=1))
print(f"wrote {out}: {len(notes)} notes, {len(bombs)} bombs, {len(walls)} walls, {len(arcs)} arcs, "
      f"{len(chains)} chains, {len(events)} events")
