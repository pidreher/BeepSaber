#!/usr/bin/env bash
# Downloads everything needed to export Open Saber for Android-based standalone
# headsets (Quest, Pico 4) from the command line:
#   - Godot editor + export templates (pinned version)
#   - Godot OpenXR Vendors addon (into addons/godotopenxrvendors, gitignored)
#   - JDK 17 (via mise if no suitable JAVA_HOME is set)
#   - Android SDK command line tools, platform-tools, build-tools, platform, NDK
#
# Re-running is safe; already present pieces are skipped.
#
# Overridable env vars:
#   TOOLCHAIN_DIR   where Godot is unpacked      (default: ~/.local/share/opensaber-toolchain)
#   ANDROID_HOME    Android SDK location         (default: ~/Android/Sdk)
#   JAVA_HOME       JDK 17 location              (default: installed via mise)
set -euo pipefail

GODOT_VERSION="4.6.3"
GODOT_TAG="${GODOT_VERSION}-stable"
VENDORS_TAG="4.3.0-stable"
CMDLINE_TOOLS_ZIP="commandlinetools-linux-13114758_latest.zip"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$HOME/.local/share/opensaber-toolchain}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
GODOT_BIN="$TOOLCHAIN_DIR/Godot_v${GODOT_TAG}_linux.x86_64"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"

mkdir -p "$TOOLCHAIN_DIR"
dl() { curl -fL --retry 3 -o "$2" "$1"; }

# --- Godot editor ---------------------------------------------------------
if [[ ! -x "$GODOT_BIN" ]]; then
	echo ">> Downloading Godot $GODOT_TAG"
	dl "https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_linux.x86_64.zip" "$TOOLCHAIN_DIR/godot.zip"
	unzip -o -q "$TOOLCHAIN_DIR/godot.zip" -d "$TOOLCHAIN_DIR"
	rm "$TOOLCHAIN_DIR/godot.zip"
	chmod +x "$GODOT_BIN"
fi

# --- Export templates -----------------------------------------------------
if [[ ! -f "$TEMPLATES_DIR/android_source.zip" ]]; then
	echo ">> Downloading Godot $GODOT_TAG export templates (~1 GB)"
	dl "https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_export_templates.tpz" "$TOOLCHAIN_DIR/templates.tpz"
	tmp="$(mktemp -d "$TOOLCHAIN_DIR/tpl.XXXX")"
	unzip -q "$TOOLCHAIN_DIR/templates.tpz" -d "$tmp"
	mkdir -p "$TEMPLATES_DIR"
	cp -r "$tmp"/templates/. "$TEMPLATES_DIR"/
	rm -rf "$tmp" "$TOOLCHAIN_DIR/templates.tpz"
fi

# --- OpenXR vendors addon -------------------------------------------------
if [[ ! -f "$PROJECT_DIR/addons/godotopenxrvendors/plugin.gdextension" ]]; then
	echo ">> Downloading Godot OpenXR Vendors $VENDORS_TAG"
	tmp="$(mktemp -d "$TOOLCHAIN_DIR/vendors.XXXX")"
	dl "https://github.com/GodotVR/godot_openxr_vendors/releases/download/${VENDORS_TAG}/godotopenxrvendorsaddon.zip" "$tmp/vendors.zip"
	unzip -q "$tmp/vendors.zip" -d "$tmp"
	rm -rf "$PROJECT_DIR/addons/godotopenxrvendors"
	cp -r "$(find "$tmp" -type d -name godotopenxrvendors | head -n1)" "$PROJECT_DIR/addons/"
	rm -rf "$tmp"
fi

# --- JDK 17 ---------------------------------------------------------------
if [[ -z "${JAVA_HOME:-}" ]] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q '"17'; then
	echo ">> Installing JDK 17 via mise"
	mise install java@temurin-17 >/dev/null
	JAVA_HOME="$(mise where java@temurin-17)"
fi
export JAVA_HOME

# --- Android SDK ----------------------------------------------------------
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [[ ! -x "$SDKMANAGER" ]]; then
	echo ">> Downloading Android command line tools"
	mkdir -p "$ANDROID_HOME/cmdline-tools"
	tmp="$(mktemp -d "$TOOLCHAIN_DIR/sdk.XXXX")"
	dl "https://dl.google.com/android/repository/${CMDLINE_TOOLS_ZIP}" "$tmp/tools.zip"
	unzip -q "$tmp/tools.zip" -d "$tmp"
	rm -rf "$ANDROID_HOME/cmdline-tools/latest"
	mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
	rm -rf "$tmp"
fi

# Versions required by the Godot gradle template (see config.gradle in android_source.zip)
cfg="$(unzip -p "$TEMPLATES_DIR/android_source.zip" config.gradle)"
build_tools="$(sed -n "s/.*buildTools *: *'\([^']*\)'.*/\1/p" <<<"$cfg")"
compile_sdk="$(sed -n "s/.*compileSdk *: *\([0-9]*\).*/\1/p" <<<"$cfg")"
ndk="$(sed -n "s/.*ndkVersion *: *'\([^']*\)'.*/\1/p" <<<"$cfg")"
echo ">> Installing Android SDK packages (build-tools $build_tools, android-$compile_sdk, ndk $ndk)"
yes | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" --licenses >/dev/null || true
"$SDKMANAGER" --sdk_root="$ANDROID_HOME" "platform-tools" "build-tools;$build_tools" "platforms;android-$compile_sdk" "ndk;$ndk" >/dev/null

cat <<EOF

Toolchain ready.
  GODOT_BIN=$GODOT_BIN
  ANDROID_HOME=$ANDROID_HOME
  JAVA_HOME=$JAVA_HOME
EOF
