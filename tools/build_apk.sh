#!/usr/bin/env bash
# Exports an Android APK for a standalone headset from the command line.
#
#   tools/build_apk.sh pico4        -> build/OpenSaberPlus-Pico4.apk
#   tools/build_apk.sh quest        -> build/OpenSaberPlus-Quest.apk
#   tools/build_apk.sh pico4 debug  -> debug build (slower, remote-debuggable)
#
# Run tools/setup_toolchain.sh once first.
#
# Release builds are signed with GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}
# if set; otherwise a personal keystore is generated in $TOOLCHAIN_DIR on first use.
# Keep that keystore: Android refuses to update an app signed with a different key.
set -euo pipefail

TARGET="${1:-pico4}"
MODE="${2:-release}"
GODOT_VERSION="4.6.3"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$HOME/.local/share/opensaber-toolchain}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
GODOT_BIN="${GODOT_BIN:-$TOOLCHAIN_DIR/Godot_v${GODOT_VERSION}-stable_linux.x86_64}"
if [[ -z "${JAVA_HOME:-}" ]]; then
	JAVA_HOME="$(mise where java@temurin-17)"
fi
export JAVA_HOME

case "$TARGET" in
	pico4) PRESET="Pico 4 (RELEASE)"; OUT="OpenSaberPlus-Pico4" ;;
	quest) PRESET="Oculus Quest (RELEASE)"; OUT="OpenSaberPlus-Quest" ;;
	*) echo "unknown target '$TARGET' (use pico4 or quest)" >&2; exit 1 ;;
esac
[[ "$MODE" == "release" || "$MODE" == "debug" ]] || { echo "mode must be release or debug" >&2; exit 1; }
[[ "$MODE" == "debug" ]] && OUT="$OUT-debug"

[[ -x "$GODOT_BIN" ]] || { echo "Godot not found, run tools/setup_toolchain.sh" >&2; exit 1; }
[[ -f "$PROJECT_DIR/addons/godotopenxrvendors/plugin.gdextension" ]] || { echo "OpenXR vendors addon missing, run tools/setup_toolchain.sh" >&2; exit 1; }

# Godot needs the SDK paths in its editor settings for exporting
settings="$HOME/.config/godot/editor_settings-${GODOT_VERSION%.*}.tres"
if [[ ! -f "$settings" ]]; then
	"$GODOT_BIN" --headless --path "$PROJECT_DIR" --quit >/dev/null 2>&1 || true
fi
sed -i \
	-e "s|^export/android/java_sdk_path = .*|export/android/java_sdk_path = \"$JAVA_HOME\"|" \
	-e "s|^export/android/android_sdk_path = .*|export/android/android_sdk_path = \"$ANDROID_HOME\"|" \
	"$settings"
grep -q '^export/android/java_sdk_path' "$settings" || \
	echo "export/android/java_sdk_path = \"$JAVA_HOME\"" >> "$settings"

if [[ "$MODE" == "release" && -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]]; then
	ks="$TOOLCHAIN_DIR/opensaber-release.keystore"
	pwfile="$TOOLCHAIN_DIR/opensaber-release.password"
	if [[ ! -f "$ks" ]]; then
		echo ">> Generating personal release keystore $ks"
		umask 077
		head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$pwfile"
		"$JAVA_HOME/bin/keytool" -genkeypair -keystore "$ks" -alias opensaber \
			-storepass "$(cat "$pwfile")" -keypass "$(cat "$pwfile")" \
			-keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Open Saber" >/dev/null
	fi
	export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$ks"
	export GODOT_ANDROID_KEYSTORE_RELEASE_USER="opensaber"
	GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$pwfile")"
	export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
fi

cd "$PROJECT_DIR"
# Fresh gradle template every time, the Quest build patches its manifest
rm -rf android/build
mkdir -p build && touch build/.gdignore
# (same as Project > Install Android Build Template)
mkdir -p android/build
unzip -q "$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable/android_source.zip" -d android/build
touch android/build/.gdignore
printf '%s' "${GODOT_VERSION}.stable" > android/.build_version
if [[ "$TARGET" == "quest" ]]; then
	# adds the Quest passthrough splash screen meta-data
	cp android_build_src_main_AndroidManifest.xml android/build/src/main/AndroidManifest.xml
fi

echo ">> Exporting '$PRESET' ($MODE)"
"$GODOT_BIN" --headless --path . "--export-$MODE" "$PRESET" "build/$OUT.apk"
ls -lh "build/$OUT.apk"
