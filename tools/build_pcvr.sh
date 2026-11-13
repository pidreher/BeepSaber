#!/usr/bin/env bash
# Export native SteamVR/OpenXR builds using Godot and its desktop templates.
# Usage: tools/build_pcvr.sh [all|linux|windows] [release|debug]
set -euo pipefail

TARGET="${1:-all}"
MODE="${2:-release}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$HOME/.local/share/opensaber-toolchain}"
GODOT_BIN="${GODOT_BIN:-$TOOLCHAIN_DIR/Godot_v4.6.3-stable_linux.x86_64}"

case "$TARGET" in
	all) targets=(linux windows) ;;
	linux|windows) targets=("$TARGET") ;;
	*) echo "unknown target '$TARGET' (use all, linux or windows)" >&2; exit 1 ;;
esac
[[ "$MODE" == release || "$MODE" == debug ]] || { echo "mode must be release or debug" >&2; exit 1; }
[[ -x "$GODOT_BIN" ]] || { echo "Godot not found at $GODOT_BIN. Set GODOT_BIN to Godot 4.6.3 and install its export templates." >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required to package the builds" >&2; exit 1; }

cd "$PROJECT_DIR"
mkdir -p build/pcvr
touch build/.gdignore
# Imports are needed on a fresh checkout, including desktop texture variants.
"$GODOT_BIN" --headless --xr-mode off --path . --editor --import --quit

for target in "${targets[@]}"; do
	suffix=""
	[[ "$MODE" == debug ]] && suffix="-debug"
	bundle="build/pcvr/$target$suffix"
	archive="build/OpenSaberPlus-SteamVR-$target$suffix.zip"
	mkdir -p "$bundle"
	case "$target" in
		linux) preset="Linux/X11"; executable="OpenSaber.x86_64" ;;
		windows) preset="Windows Desktop"; executable="OpenSaber.exe" ;;
	esac
	echo ">> Exporting $preset ($MODE)"
	"$GODOT_BIN" --headless --xr-mode off --path . "--export-$MODE" "$preset" "$bundle/$executable"
	if [[ "$target" == linux ]]; then
		cat > "$bundle/Launch-SteamVR.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bundle_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$bundle_dir/OpenSaber.x86_64" --xr-mode on --rendering-method mobile --rendering-driver vulkan "$@"
EOF
		chmod +x "$bundle/Launch-SteamVR.sh"
	else
		cat > "$bundle/Launch-SteamVR.cmd" <<'EOF'
@echo off
"%~dp0OpenSaber.exe" --xr-mode on --rendering-method mobile --rendering-driver vulkan %*
EOF
	fi
	cp doc/steamvr.md "$bundle/README-SteamVR.md"
	cp LICENSE "$bundle/LICENSE"
	cp icon.png "$bundle/icon.png"
	cp tools/add_to_steam.py "$bundle/Add-to-Steam.py"
	# Include the vendor extension's shared libraries as well as the executable.
	python3 - "$bundle" "$archive" <<'PY'
from pathlib import Path
import sys
import zipfile

bundle, archive = map(Path, sys.argv[1:])
with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as package:
    for path in sorted(bundle.rglob("*")):
        if path.is_file():
            package.write(path, Path("OpenSaberPlus-SteamVR") / path.relative_to(bundle))
print(f">> Ready: {archive} ({archive.stat().st_size / 1024 / 1024:.1f} MiB)")
PY
done
