#!/usr/bin/env bash
# Records the App Preview / header-video flow: starts `simctl io recordVideo` on a simulator, runs the
# slow UI test (ScreenshotTests/testClipFlow) on that same simulator, then stops the recording.
#
# Usage:  scripts/record_clip.sh iphone     # iPhone 6.9"            -> clip_iphone_flow.mov
#         scripts/record_clip.sh duo_inner  # iPhone Duo, unfolded   -> clip_duo_inner_flow.mov
#
# The Duo's inner display must be unfolded in Device Hub first (a folded Duo records a black screen).
# Raw length is kept; the video is trimmed afterwards. No audio is recorded.
#
# The recording goes to a scratch directory and is then moved into OUT_DIR WITHOUT overwriting.
set -euo pipefail

TARGET="${1:-iphone}"
case "$TARGET" in
  iphone)    NAME="iPhone 17 Pro Max"; ORIENT=portrait;  OUTNAME="clip_iphone_flow.mov";    TAG=iphone69 ;;
  duo_inner) NAME="iPhone Duo";        ORIENT=landscape; OUTNAME="clip_duo_inner_flow.mov"; TAG=duo_inner ;;
  *) echo "usage: $0 iphone|duo_inner" >&2; exit 2 ;;
esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/ClaudeCoWork/Personal-App-Development/EET/raw}"
SCRATCH="${SCRATCH:-/tmp/eet-clips}"
mkdir -p "$SCRATCH" "$OUT_DIR"
RAW="$SCRATCH/$OUTNAME"

UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; print([d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['name']=='$NAME'][-1])")
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null \
  || echo "note: status bar override not available for $NAME"

echo "▶︎ building the tests"
xcodebuild build-for-testing -project "$REPO/ExerciseTimer.xcodeproj" -scheme ExerciseTimer -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "${DERIVED:-/tmp/eet-clip-dd}" -quiet

rm -f "$RAW"
echo "▶︎ recording $NAME -> $RAW"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$RAW" &
REC=$!
trap 'kill -INT "$REC" 2>/dev/null || true' EXIT
sleep 2   # let the recorder attach

# -parallel-testing-enabled NO: run on this simulator itself (a clone would be recorded as an idle screen).
TEST_RUNNER_SCREENSHOT_DEVICE="$TAG" TEST_RUNNER_SCREENSHOT_LANG=en TEST_RUNNER_SCREENSHOT_ORIENTATION="$ORIENT" \
TEST_RUNNER_SCREENSHOT_SLOW="${SLOW:-2.5}" \
xcodebuild test-without-building -project "$REPO/ExerciseTimer.xcodeproj" -scheme ExerciseTimer -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "${DERIVED:-/tmp/eet-clip-dd}" \
  -parallel-testing-enabled NO -only-testing:ExerciseTimerUITests/ScreenshotTests/testClipFlow -quiet

sleep 2
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
trap - EXIT

SECS=$(mdls -raw -name kMDItemDurationSeconds "$RAW" 2>/dev/null || echo "?")
echo "  recorded $RAW  (${SECS}s)"
if [[ -e "$OUT_DIR/$OUTNAME" ]]; then
  echo "  skipped: $OUT_DIR/$OUTNAME already exists (left untouched; recording kept at $RAW)"
else
  mv -n "$RAW" "$OUT_DIR/$OUTNAME" && echo "  saved   $OUT_DIR/$OUTNAME"
fi
