#!/bin/zsh
# Direct App Store captures WITHOUT xcodebuild test.
#
# `xcodebuild test` runs on a *clone* of the simulator: the clone boots folded (Duo) and doesn't
# inherit the 9:41 status-bar override (iPad). This script builds once, installs onto the simulator
# you already set up (booted, unfolded, rotated), and drives each scene with the app's own
# -screenshotMode / -screenshotScene launch arguments.
#
# Run from the ExpandableExerciseTimer repo (branch appstore-captures-3.0):
#   Duo inner (default):  zsh capture_direct.sh
#   iPad 13" landscape:   DEVICE_NAME="<exact iPad simulator name>" PREFIX=ipad13 zsh capture_direct.sh
#   Only some scenes:     SCENES="01:plan 07:recap" zsh capture_direct.sh
# If DEVICE_NAME doesn't match, the script lists the booted simulators.
set -euo pipefail

REPO=${REPO:-$PWD}
DEVICE_NAME=${DEVICE_NAME:-"iPhone Duo"}
PREFIX=${PREFIX:-duo_inner}
BUNDLE="rocks.scruggsfam.productions.ExpandableExerciseTimer"
OUT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/ClaudeCoWork/Personal-App-Development/EET/raw"
DD=/tmp/eet-direct-dd
SCENE_LIST=${SCENES:-01:plan 02:manualSet 03:superset 05:restLog 06:overview 07:recap}
SCENE_ARRAY=(${=SCENE_LIST})   # split on spaces

# Expected App Store sizes (landscape) and display selection per prefix.
case "$PREFIX" in
  duo_inner) EXPECT="2853x2007"; DISPLAY_NUM=${DISPLAY_NUM:-3} ;;   # inner display on the Duo simulator
  ipad13)    EXPECT="2752x2064"; DISPLAY_NUM=${DISPLAY_NUM:-} ;;
  *)         EXPECT="";          DISPLAY_NUM=${DISPLAY_NUM:-} ;;
esac
DISPLAY_ARG=(); [[ -n "$DISPLAY_NUM" ]] && DISPLAY_ARG=(--display="$DISPLAY_NUM")

[[ -d "$REPO/ExerciseTimer.xcodeproj" ]] || { echo "Run this from the repo (or set REPO=...)."; exit 1; }
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices booted -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["name"] == name and d["state"] == "Booted":
            print(d["udid"]); raise SystemExit
' "$DEVICE_NAME")
if [[ -z "$UDID" ]]; then
  echo "No booted simulator named '$DEVICE_NAME'. Booted simulators:"
  xcrun simctl list devices booted | grep -v "^==" | sed 's/^/  /'
  exit 1
fi
echo "▶︎ $PREFIX on $DEVICE_NAME ($UDID)"

echo "▶︎ Building (Debug, so screenshot mode is included)…"
xcodebuild -project "$REPO/ExerciseTimer.xcodeproj" -scheme ExerciseTimer -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DD" build -quiet
APP=$(find "$DD/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "*.app" ! -name "*Tests*" | head -n 1)
[[ -n "$APP" ]] || { echo "Built app not found under $DD."; exit 1; }
xcrun simctl install "$UDID" "$APP"

# 9:41 today, as a strict UTC ISO-8601 string, so iPad (which also shows the date) reads 9:41.
# If simctl rejects it, fall back to the plain "9:41" string that works on iPhone.
EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 09:41:00" +%s)
ISO_TIME=$(date -u -r "$EPOCH" +%Y-%m-%dT%H:%M:%SZ)
SB_ARGS=(--batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3)
if ! xcrun simctl status_bar "$UDID" override --time "$ISO_TIME" "${SB_ARGS[@]}" 2>/dev/null; then
  echo "  (ISO time rejected; using plain 9:41)"
  xcrun simctl status_bar "$UDID" override --time "9:41" "${SB_ARGS[@]}" || true
fi

echo
read "?Confirm the simulator is set up (unfolded / LANDSCAPE as needed), then press Return… "

set +e
failed=0
for entry in "${SCENE_ARRAY[@]}"; do
  num=${entry%%:*}; scene=${entry#*:}
  file="$OUT/${PREFIX}_en_${num}_${scene}.png"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
  if ! xcrun simctl launch "$UDID" "$BUNDLE" -screenshotMode -screenshotScene "$scene" >/dev/null; then
    echo "✗ $scene: launch failed (see the error above)"; failed=1; continue
  fi
  sleep 5
  # Capture to /tmp first, then move into place from this shell. The simulator can't overwrite
  # files another process created in raw/ (e.g. the plugin's exports), even when they look writable.
  tmp="/tmp/eet_capture_$$.png"; rm -f "$tmp"
  if ! xcrun simctl io "$UDID" screenshot --type=png "${DISPLAY_ARG[@]}" "$tmp" >/dev/null; then
    echo "✗ $scene: screenshot failed (see the error above). For a two-display device, rerun with DISPLAY_NUM=<number>."
    failed=1; continue
  fi
  if ! mv -f "$tmp" "$file"; then
    echo "✗ $scene: couldn't replace $(basename "$file"). Move the old file out of raw/ and rerun."
    failed=1; continue
  fi
  dims=$(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w"x"h}')
  size=$(stat -f%z "$file")
  if (( size < 60000 )); then
    echo "⚠️  $scene: $(basename "$file") is only $size bytes. Probably blank."
  elif [[ -n "$EXPECT" && "$dims" != "$EXPECT" ]]; then
    echo "⚠️  $scene: $(basename "$file") is $dims, expected $EXPECT. Check the orientation."
  else
    echo "✓ $scene → $(basename "$file") ($dims)"
  fi
done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
(( failed )) && echo "Some scenes failed. Copy everything above into the chat."
echo "Done."
