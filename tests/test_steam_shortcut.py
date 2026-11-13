"""Validate library edits against isolated Steam profiles, never the real account."""

import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "add_to_steam", Path(__file__).resolve().parents[1] / "tools/add_to_steam.py")
steam = importlib.util.module_from_spec(spec)
spec.loader.exec_module(steam)


class SteamShortcutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="opensaber steam test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "Steam"
        self.profile = self.root / "userdata/42/config"
        self.profile.mkdir(parents=True)
        self.shortcuts = self.profile / "shortcuts.vdf"
        self.bundle = Path(self.temp.name) / "bundle"
        self.bundle.mkdir()
        exe = "OpenSaber.exe" if steam.os.name == "nt" else "OpenSaber.x86_64"
        lib = "libgodotopenxrvendors.dll" if steam.os.name == "nt" else "libgodotopenxrvendors.so"
        for name in (exe, lib, "icon.png"):
            (self.bundle / name).write_bytes(b"fixture")

    def install(self):
        with patch.object(steam, "steam_running", return_value=False), contextlib.redirect_stdout(io.StringIO()):
            return steam.install(self.bundle, self.root)

    def test_reads_known_empty_steam_file(self):
        fixture = b"\x00shortcuts\x00\x08\x08"
        self.assertEqual(steam.read_vdf(fixture), {"shortcuts": {}})
        self.assertEqual(steam.write_vdf({"shortcuts": {}}), fixture)

    def test_preserves_existing_shortcuts_and_backs_up_original(self):
        existing = {"shortcuts": {"3": {"appid": 0xF0123456, "AppName": "Other game – 日本語",
                                       "CustomField": "preserve", "tags": {"0": "Favourites"}}}}
        original = steam.write_vdf(existing)
        self.shortcuts.write_bytes(original)
        game_id = self.install()
        saved = steam.read_vdf(self.shortcuts.read_bytes())["shortcuts"]
        self.assertEqual(saved["3"], existing["shortcuts"]["3"])
        self.assertEqual(saved["4"]["OpenVR"], 1)
        self.assertEqual(saved["4"]["LaunchOptions"], steam.LAUNCH_OPTIONS)
        self.assertEqual(game_id, (saved["4"]["appid"] << 32) | 0x02000000)
        self.assertEqual(next(self.profile.glob("*.bak")).read_bytes(), original)
        installed = self.root / "steamapps/common/OpenSaberPlus"
        self.assertIn(str(installed), saved["4"]["Exe"])
        self.assertEqual((installed / "icon.png").read_bytes(), b"fixture")

    def test_second_install_keeps_id_and_does_not_duplicate(self):
        first_id = self.install()
        original = self.shortcuts.read_bytes()
        self.assertEqual(self.install(), first_id)
        self.assertEqual(self.shortcuts.read_bytes(), original)
        self.assertEqual(len(steam.read_vdf(original)["shortcuts"]), 1)

    def test_updates_client_field_casing_and_preserves_customization(self):
        self.shortcuts.write_bytes(steam.write_vdf({"shortcuts": {"0": {
            "appid": 0xDEADBEEF, "appname": steam.APP_NAME, "exe": "old location",
            "launchoptions": "old flags", "openvr": 0, "tags": {"0": "My collection"}}}}))
        self.install()
        saved = steam.read_vdf(self.shortcuts.read_bytes())["shortcuts"]["0"]
        self.assertEqual(saved["appid"], 0xDEADBEEF)
        self.assertEqual(saved["tags"], {"0": "My collection"})
        self.assertEqual(saved["openvr"], 1)
        self.assertEqual(saved["launchoptions"], steam.LAUNCH_OPTIONS)
        self.assertNotIn("Exe", saved)

    def test_running_steam_refuses_without_mutating_profile(self):
        original = b"\x00shortcuts\x00\x08\x08"
        self.shortcuts.write_bytes(original)
        with patch.object(steam, "steam_running", return_value=True):
            with self.assertRaisesRegex(ValueError, "Exit Steam"):
                steam.install(self.bundle, self.root)
        self.assertEqual(self.shortcuts.read_bytes(), original)
        self.assertFalse((self.root / "steamapps").exists())

    def test_unknown_or_truncated_data_is_not_overwritten(self):
        for original in (b"\x00shortcuts\x00\x03unknown\x00\x08\x08", b"\x00shortcuts\x00"):
            self.shortcuts.write_bytes(original)
            with self.assertRaises(ValueError):
                self.install()
            self.assertEqual(self.shortcuts.read_bytes(), original)

    def test_multiple_accounts_require_explicit_selection(self):
        (self.root / "userdata/99/config").mkdir(parents=True)
        with self.assertRaisesRegex(ValueError, "--user-id"):
            self.install()
        self.assertFalse(self.shortcuts.exists())
        self.assertEqual(steam.choose_profile(self.root, "42"), self.profile.parent)


if __name__ == "__main__":
    unittest.main()
