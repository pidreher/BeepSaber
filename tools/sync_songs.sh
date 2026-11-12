#!/usr/bin/env bash
# Copies Beat Saber custom songs (one folder per song with an Info.dat) to the
# headset connected via adb. Songs already on the headset are skipped.
#
#   tools/sync_songs.sh [SOURCE_DIR]
#
# SOURCE_DIR defaults to $BEATSABER_SONGS or the CustomLevels folder of a
# Steam Beat Saber install.
set -euo pipefail

PACKAGE="${PACKAGE:-org.godotengine.open_saber_plus}"
DEST="/sdcard/Android/data/$PACKAGE/files/Songs"

SRC="${1:-${BEATSABER_SONGS:-}}"
if [[ -z "$SRC" ]]; then
	for lib in "$HOME/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" /var/mnt/*/SteamLibrary /mnt/*/SteamLibrary /run/media/*/*/SteamLibrary; do
		cand="$lib/steamapps/common/Beat Saber/Beat Saber_Data/CustomLevels"
		if [[ -d "$cand" ]]; then SRC="$cand"; break; fi
	done
fi
[[ -d "$SRC" ]] || { echo "no song folder found, pass it as argument" >&2; exit 1; }

adb get-state >/dev/null
adb shell mkdir -p "\"$DEST\""
existing="$(adb shell ls -1 "\"$DEST\"" 2>/dev/null | tr -d '\r')"

copied=0; skipped=0
for dir in "$SRC"/*/; do
	name="$(basename "$dir")"
	if [[ ! -f "$dir/Info.dat" && ! -f "$dir/info.dat" ]]; then
		continue
	fi
	if grep -qxF "$name" <<<"$existing"; then
		skipped=$((skipped + 1)); continue
	fi
	echo ">> $name"
	adb push "$dir" "$DEST/" >/dev/null
	copied=$((copied + 1))
done
echo "copied $copied songs, $skipped already on the headset ($DEST)"
