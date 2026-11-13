#!/usr/bin/env python3
"""Install a PC VR bundle and register its non-Steam VR library shortcut.

Exit Steam first. Uses only the Python standard library and supports native
Linux Steam, Flatpak Steam and Windows Steam. Existing shortcuts are preserved.
"""

import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zlib

APP_NAME = "Open Saber Plus"
LAUNCH_OPTIONS = "--xr-mode on --rendering-method mobile --rendering-driver vulkan"


def read_vdf(data):
    """Read the object, UTF-8 string and uint32 types used by shortcuts.vdf.

    Reject unsupported or malformed records before making any changes.
    """
    offset = 0

    def string():
        nonlocal offset
        end = data.index(b"\0", offset)
        value = data[offset:end].decode("utf-8", errors="surrogateescape")
        offset = end + 1
        return value

    def object_value():
        nonlocal offset
        result = {}
        while offset < len(data):
            kind = data[offset]
            offset += 1
            if kind == 8:
                return result
            key = string()
            if key in result:
                raise ValueError(f"Duplicate Steam shortcut field: {key}")
            if kind == 0:
                result[key] = object_value()
            elif kind == 1:
                result[key] = string()
            elif kind == 2:
                if offset + 4 > len(data):
                    raise ValueError("Truncated Steam shortcut integer")
                result[key] = struct.unpack_from("<I", data, offset)[0]
                offset += 4
            else:
                raise ValueError(f"Unsupported Steam shortcut value type: {kind}")
        raise ValueError("Truncated Steam shortcuts file")

    result = object_value()
    if offset != len(data) or not isinstance(result.get("shortcuts"), dict):
        raise ValueError("Invalid Steam shortcuts file")
    return result


def write_vdf(value):
    result = bytearray()
    for key, item in value.items():
        kind = 0 if isinstance(item, dict) else 1 if isinstance(item, str) else 2
        result.append(kind)
        result.extend(key.encode("utf-8", errors="surrogateescape") + b"\0")
        if kind == 0:
            result.extend(write_vdf(item))
        elif kind == 1:
            result.extend(item.encode("utf-8", errors="surrogateescape") + b"\0")
        elif isinstance(item, int):
            result.extend(struct.pack("<I", item))
        else:
            raise ValueError("Invalid Steam shortcut value")
    result.append(8)
    return bytes(result)


def steam_running():
    if os.name == "nt":
        processes = subprocess.check_output(
            ["tasklist", "/FI", "IMAGENAME eq steam.exe", "/FO", "CSV", "/NH"],
            text=True,
        )
        return '"steam.exe"' in processes.lower()
    for process in Path("/proc").glob("[0-9]*/comm"):
        try:
            if process.read_text().strip() == "steam":
                return True
        except (OSError, UnicodeError):
            continue
    return False


def find_steam_root():
    home = Path.home()
    candidates = [
        home / ".steam/steam", home / ".steam/root", home / ".local/share/Steam",
        home / ".var/app/com.valvesoftware.Steam/.local/share/Steam",
    ]
    if os.name == "nt":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as key:
                candidates.insert(0, Path(winreg.QueryValueEx(key, "SteamPath")[0]))
        except OSError:
            pass
    roots = list(dict.fromkeys(p.resolve() for p in candidates if (p / "userdata").is_dir()))
    if len(roots) != 1:
        raise ValueError("Could not choose a Steam installation. Supply --steam-root PATH.")
    return roots[0]


def choose_profile(root, user_id=None):
    profiles = [p for p in (root / "userdata").iterdir() if p.is_dir() and p.name.isdecimal()]
    if user_id:
        profiles = [p for p in profiles if p.name == user_id]
    if len(profiles) != 1:
        raise ValueError("Could not choose a Steam account. Supply --user-id with its userdata folder number.")
    return profiles[0]


def update_shortcut(document, install_dir, executable):
    shortcuts = document["shortcuts"]
    quoted_exe = f'"{install_dir / executable}"'
    matches = [s for s in shortcuts.values() if isinstance(s, dict)
               and next((v for k, v in s.items() if k.lower() == "appname"), None) == APP_NAME]
    if len(matches) > 1:
        raise ValueError("Multiple Open Saber Plus shortcuts exist; remove duplicates in Steam first.")
    if matches:
        entry = matches[0]
    else:
        if any(not key.isdecimal() for key in shortcuts):
            raise ValueError("Invalid Steam shortcut index")
        index = str(max((int(key) for key in shortcuts), default=-1) + 1)
        entry = {
            "appid": zlib.crc32((quoted_exe + APP_NAME).encode()) | 0x80000000,
            "AppName": APP_NAME, "ShortcutPath": "", "IsHidden": 0,
            "AllowDesktopConfig": 1, "AllowOverlay": 1, "Devkit": 0,
            "DevkitGameID": "", "DevkitOverrideAppID": 0, "LastPlayTime": 0,
            "FlatpakAppID": "", "tags": {"0": "VR"},
        }
        shortcuts[index] = entry
    fields = {key.lower(): key for key in entry}
    for key, value in dict(Exe=quoted_exe, StartDir=f'"{install_dir}"',
                           icon=str(install_dir / "icon.png"), LaunchOptions=LAUNCH_OPTIONS, OpenVR=1).items():
        entry[fields.get(key.lower(), key)] = value
    return entry["appid"]


def install(bundle, root, user_id=None):
    if steam_running():
        raise ValueError("Exit Steam using Steam > Exit, then run this installer again.")
    executable = "OpenSaber.exe" if os.name == "nt" else "OpenSaber.x86_64"
    library = "libgodotopenxrvendors.dll" if os.name == "nt" else "libgodotopenxrvendors.so"
    for filename in (executable, library, "icon.png"):
        if not (bundle / filename).is_file():
            raise ValueError(f"Missing {bundle / filename}. Build the PC VR bundle first.")
    profile = choose_profile(root, user_id)
    shortcuts_file = profile / "config/shortcuts.vdf"
    original = shortcuts_file.read_bytes() if shortcuts_file.exists() else None
    document = read_vdf(original) if original else {"shortcuts": {}}
    install_dir = root / "steamapps/common/OpenSaberPlus"
    app_id = update_shortcut(document, install_dir, executable)
    updated = write_vdf(document)
    assert read_vdf(updated) == document
    install_dir.mkdir(parents=True, exist_ok=True)
    for filename in (executable, library, "icon.png", "LICENSE", "README-SteamVR.md",
                     "Launch-SteamVR.sh", "Launch-SteamVR.cmd", "Add-to-Steam.py"):
        source, destination = bundle / filename, install_dir / filename
        if source.is_file() and source.resolve() != destination.resolve():
            shutil.copy2(source, destination)
    if steam_running():
        raise ValueError("Steam started during installation. Exit Steam and run the installer again.")
    # Check for outside edits before replacing the config; back it up intact.
    current = shortcuts_file.read_bytes() if shortcuts_file.exists() else None
    if current != original:
        raise ValueError("Steam shortcuts changed during installation. Run the installer again.")
    shortcuts_file.parent.mkdir(parents=True, exist_ok=True)
    if updated != original:
        if original is not None:
            backup = shortcuts_file.with_name(f"shortcuts.vdf.opensaber-{time.time_ns()}.bak")
            shutil.copy2(shortcuts_file, backup)
            print(f"Shortcut backup: {backup}")
        with tempfile.NamedTemporaryFile(dir=shortcuts_file.parent, delete=False) as temp:
            temp_path = Path(temp.name)
            try:
                temp.write(updated)
                temp.flush()
                os.fsync(temp.fileno())
            except BaseException:
                temp_path.unlink(missing_ok=True)
                raise
        try:
            os.replace(temp_path, shortcuts_file)
        finally:
            temp_path.unlink(missing_ok=True)
    game_id = (app_id << 32) | 0x02000000
    print(f"Installed: {install_dir}")
    print(f"Steam library: {APP_NAME} (VR)")
    print(f"Launch URL: steam://rungameid/{game_id}")
    print("Start Steam and press Play on Open Saber Plus. Connect your headset to SteamVR first.")
    return game_id


def main():
    here = Path(__file__).resolve().parent
    default_bundle = here.parent / "build/pcvr" / ("windows" if os.name == "nt" else "linux") if here.name == "tools" else here
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, default=default_bundle)
    parser.add_argument("--steam-root", type=Path)
    parser.add_argument("--user-id")
    args = parser.parse_args()
    try:
        if sys.platform not in ("linux", "win32"):
            raise ValueError("This installer supports Windows and Linux Steam.")
        install(args.bundle.resolve(), (args.steam_root or find_steam_root()).resolve(), args.user_id)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
