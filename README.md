# Open Saber Plus VR
This is a fork of [Beep Saber by NeoSpark314](https://github.com/NeoSpark314/BeepSaber) ported to Godot 4.6 and OpenXR (WIP)
(The OQ Toolkit is only partially ported/patched for it to work on Godot 4 with OpenXR, most features that are not used in this project will not work)

This fork tries to improve the experience and make it more of it's own game instead of just a demo.



This is a basic implementation of the beat saber game mechanic for VR using the [Godot Game Engine](https://godotengine.org/) and the [Godot Oculus Quest Toolkit](https://github.com/NeoSpark314/godot_oculus_quest_toolkit). The main objective of this project is to show how a VR game can be implemented using
the Godot game engine.

The main target platforms are the Meta Quest and Pico 4 / Pico 4 Ultra standalone headsets. It should also work with SteamVR or other PC OpenXR runtimes.

Originally this game was (and still is) a demo game as part of the Godot Oculus Quest Toolkit. To keep the demo implementation small
this stand alone version was forked so that it can be changed and developed independent of the original demo.

![screenshot01](doc/images/OS0.4.0_1.gif)
![screenshot02](doc/images/OS0.4.0_2.gif)
![screenshot03](doc/images/OS0.4.0_3.gif)
# About the implementation
This game uses Godot 4.6. The implementation supports to load and play maps from [BeatSaver](https://beatsaver.com/)
(beatmap formats v2, v3 and partially v4).

There is one demo song included that is part of the deployed package.

You can play custom songs by downloading them in the in-game menu.

## Map mods
* **Chroma**: per-note, bomb, wall and lighting event colors (`_color` / `color` custom data).
  Per-light-ID effects (`_lightID`) and gradients are not supported. Turn on "Ignore Map's Colors" in the settings to ignore them.
* **Mapping Extensions**: extra lanes/layers, precise placement, 360° note rotation
  (cut directions 1000-1360 and 2000-2360) and precise wall width/height (including the v2 `_type` encodings).
* **Noodle Extensions** and **Vivify** are *not* supported; such maps load but play like vanilla maps.

The song info panel lists the mods a map requires or suggests and marks unsupported ones.

# Building for Android headsets (Pico 4, Quest)
Everything can be done from the command line on Linux:

```sh
tools/setup_toolchain.sh      # once: Godot 4.6.3 + export templates, OpenXR vendors plugin v4.3.0,
                              #       JDK 17 (via mise), Android SDK/NDK
tools/build_apk.sh pico4      # -> build/OpenSaberPlus-Pico4.apk
tools/build_apk.sh quest      # -> build/OpenSaberPlus-Quest.apk
adb install -r build/OpenSaberPlus-Pico4.apk
```

Release builds are signed with the keystore given in `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD`;
if unset, a personal keystore is generated in `~/.local/share/opensaber-toolchain/`. Keep it, Android only installs
updates signed with the same key. Use `tools/build_apk.sh pico4 debug` for a debug build.

To export from the Godot editor instead:
1. Install the [Godot OpenXR Vendors plugin](https://github.com/GodotVR/godot_openxr_vendors) v4.x into `addons/godotopenxrvendors`.
2. Project > Install Android Build Template.
3. For Quest only: copy `android_build_src_main_AndroidManifest.xml` to `android/build/src/main/AndroidManifest.xml`
   (adds the passthrough splash screen).
4. Export with the "Pico 4 (RELEASE)" or "Oculus Quest (RELEASE)" preset.

`tools/sync_songs.sh [DIR]` copies Beat Saber custom songs (default: the `CustomLevels` folder of a Steam
Beat Saber install) to the connected headset, skipping songs that are already there.

The Pico build uses the Compatibility (OpenGL ES) renderer: with Vulkan the Pico OpenXR runtime crashes
during startup.

Custom songs can also be copied to `/sdcard/Android/data/org.godotengine.open_saber_plus/files/Songs/`
on the headset, or uploaded through the built-in web uploader shown in the menu.

# Credits
The included Music Track is Time Lapse by TheFatRat (https://www.youtube.com/watch?v=3fxq7kqyWO8)

# Licensing
The source code of the godot beep saber / open saber game in this repository is licensed under an MIT License.
