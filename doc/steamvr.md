# SteamVR / PC VR

Open Saber uses Godot's built-in OpenXR support with SteamVR on Windows and
Linux (x86_64). The game runs on the PC; a Pico or Quest connects to the PC
through a SteamVR-compatible streaming connection. The standalone Android APK
is a separate build and does not run through SteamVR.

## Play

1. Extract the entire `OpenSaberPlus-SteamVR-windows.zip` or
   `OpenSaberPlus-SteamVR-linux.zip` archive. Keep the executable and shared
   libraries together.
2. Start SteamVR and connect the headset and both controllers. For a Pico 4,
   establish your PC streaming connection first and check that SteamVR sees it.
3. In SteamVR **Settings > OpenXR**, select **Set SteamVR as OpenXR Runtime**.
   Enable advanced settings if that section is hidden. Restart the game after
   changing the active runtime.
4. Run `Launch-SteamVR.cmd` on Windows or `./Launch-SteamVR.sh` on Linux.
   The executable can also be launched directly. You can add it to Steam as a
   non-Steam game; Steam launch options
   `--xr-mode on --rendering-method mobile --rendering-driver vulkan`
   explicitly select VR, the Mobile renderer and Vulkan.

These are native builds: run the Linux build directly on Linux, without Proton.
The desktop renderer is Mobile with Vulkan; the Pico standalone build retains
its Compatibility renderer.

## Add to your Steam library

The PC bundles include `Add-to-Steam.py`. With Python 3 installed, exit Steam
using **Steam > Exit**, then run this from the extracted bundle:

```sh
python3 Add-to-Steam.py   # Linux, including Flatpak Steam
```

On Windows use `py Add-to-Steam.py`. From the source checkout, run
`python3 tools/add_to_steam.py` after building your platform's PC VR bundle.
Start Steam again and find **Open Saber Plus** in your library, then press
**Play**. The shortcut is included in the VR library with the renderer and
OpenXR launch options already set.

The installer copies the game into Steam's `steamapps/common/OpenSaberPlus/`
folder so Flatpak Steam can access it. It preserves existing shortcuts, backs
up the shortcut file before changing it, and updates its own entry when run
again. If you have several Steam accounts or installations, select one with
`--user-id NUMBER` or `--steam-root PATH`.

You can also use Steam's [Add a Non-Steam Game](https://help.steampowered.com/en/faqs/view/4B8B-9697-2338-40EC)
menu: browse to `OpenSaber.exe` or `OpenSaber.x86_64`, set its launch options to
`--xr-mode on --rendering-method mobile --rendering-driver vulkan`, and enable
**Include in VR Library** in its properties. Use the native Linux build with
Steam compatibility tools disabled on Linux.

## Controls

- Aim either saber at a menu and pull its trigger to select.
- Use the joystick or Vive trackpad to scroll while pointing at a list.
- Pause with **B/Y**, a controller's **menu** button, or an **Index thumbstick
  click**. The SteamVR system button belongs to the dashboard.
- Opening the dashboard or removing the headset pauses a running song. Return
  to the game and select **Resume** to continue with a countdown.
- Use **Center & height** in the menu after setting up the play space. Seated
  play and height adjustments work the same as on standalone headsets.

The action map includes Touch, Pico, Index, Vive and Windows Mixed Reality
controller profiles. Headset and controller testing is still needed for each
PC streaming setup.

## Build from source

Install Godot **4.6.3** and its export templates. From Linux or a compatible
Bash environment, run:

```sh
tools/build_pcvr.sh             # both Windows and Linux release ZIPs
tools/build_pcvr.sh windows     # Windows only
tools/build_pcvr.sh linux debug # Linux debug ZIP
```

The script reuses Godot from `~/.local/share/opensaber-toolchain/` if present.
Set `GODOT_BIN=/path/to/godot` to use another installation. Python 3 packages
the ZIPs. No Android SDK, JDK or signing key is needed for desktop exports.
Outputs are in `build/pcvr/` with distributable ZIPs in `build/`.

In the Godot editor, use the **Windows Desktop** or **Linux/X11** export preset.
Both enable the `pcvr` feature and include map data, cover art and uploader
assets. Enable S3TC/BPTC imports when opening an older checkout.

Downloaded songs and settings use Godot's per-user application data folder:

- Windows songs: `%APPDATA%\Godot\app_userdata\Open Saber\OpenSaber\Songs\`
- Linux songs: `~/.local/share/godot/app_userdata/Open Saber/OpenSaber/Songs/`
  (or under `$XDG_DATA_HOME` if set).

## Troubleshooting

If a VR startup alert or the keyboard simulator appears, close the game, check
that SteamVR can see the headset, select SteamVR as the active OpenXR runtime,
then relaunch. An `XR_RUNTIME_JSON` environment variable overrides the runtime
selection; check it if the wrong runtime keeps starting. On Linux you can set
it to the absolute path to SteamVR's `steamxr_linux64.json` for a single launch.

Use a GPU and driver with Vulkan support. Launch the debug executable from a
terminal (or use the Windows console wrapper) to inspect OpenXR errors. For a
desktop-only preview, run the executable with `--xr-mode off`.

Godot documents the [OpenXR setup and runtime requirements](https://docs.godotengine.org/en/4.6/tutorials/xr/openxr_settings.html)
and the [recommended desktop XR renderer](https://docs.godotengine.org/en/4.6/tutorials/xr/setting_up_xr.html).
