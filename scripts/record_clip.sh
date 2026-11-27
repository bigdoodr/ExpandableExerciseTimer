#!/usr/bin/env bash
# Records the App Preview / header-video flow: starts `simctl io recordVideo` on a simulator, runs the
# slow UI test (ScreenshotTests/testClipFlow) on that same simulator, then stops the recording.
#
# Usage:  scripts/record_clip.sh iphone     # iPhone 6.9"            -> clip_iphone_flow.mov
#         scripts/record_clip.sh duo_inner  # iPhone Duo, unfolded   -> clip_duo_inner_flow.mov
#
# The Duo's inner display must be unfolded in Device Hub first (a folded Duo records a black screen),
# and rotated to landscape. Like scripts/capture_direct.sh this uses the simulator you have set up (the
# booted one) and never a clone: the UI test runs with -parallel-testing-enabled NO, and the recording
# targets the Duo's inner display (--display, 3 by default, as in capture_direct.sh).
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

# Prefer the simulator that is already booted (the one you set up); otherwise boot the newest match.
UDID=$(xcrun simctl list devices booted -j | python3 -c "import json,sys; m=[d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['name']=='$NAME']; print(m[-1] if m else '')")
if [[ -z "$UDID" ]]; then
  UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; print([d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['name']=='$NAME'][-1])")
  xcrun simctl boot "$UDID" 2>/dev/null || true
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
DISPLAY_ARG=()
if [[ "$TARGET" == duo_inner ]]; then
  DISPLAY_ARG=(--display="${DISPLAY_NUM:-3}")
  read -r -p "Confirm the Duo is unfolded (inner display) and rotated to landscape, then press Return… " _ \
    || echo "(no terminal: continuing)"
fi
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null \
  || echo "note: status bar override not available for $NAME"

echo "▶︎ building the tests"
xcodebuild build-for-testing -project "$REPO/ExerciseTimer.xcodeproj" -scheme ExerciseTimer -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "${DERIVED:-/tmp/eet-clip-dd}" -quiet

rm -f "$RAW" /tmp/eet-clip-started /tmp/eet-clip-finished

# The test runs in the background. The recorder starts when the test's own "started" marker appears
# (not before: installing the runner takes ~25 s of home screen) and stops after its "finished" one.
# -parallel-testing-enabled NO: run on this simulator itself (a clone would be recorded as an idle screen).
TEST_RUNNER_SCREENSHOT_DEVICE="$TAG" TEST_RUNNER_SCREENSHOT_LANG=en TEST_RUNNER_SCREENSHOT_ORIENTATION="$ORIENT" \
TEST_RUNNER_SCREENSHOT_SLOW="${SLOW:-2.5}" \
xcodebuild test-without-building -project "$REPO/ExerciseTimer.xcodeproj" -scheme ExerciseTimer -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "${DERIVED:-/tmp/eet-clip-dd}" \
  -parallel-testing-enabled NO -only-testing:ExerciseTimerUITests/ScreenshotTests/testClipFlow -quiet &
TEST=$!

for _ in $(seq 1 240); do [[ -e /tmp/eet-clip-started ]] && break; sleep 0.5; done
if [[ ! -e /tmp/eet-clip-started ]]; then echo "note: no start marker from the test; recording from now"; fi
echo "▶︎ recording $NAME -> $RAW"
xcrun simctl io "$UDID" recordVideo ${DISPLAY_ARG[@]+"${DISPLAY_ARG[@]}"} --codec h264 --force "$RAW" &
REC=$!
trap 'kill -INT "$REC" 2>/dev/null || true' EXIT

for _ in $(seq 1 600); do [[ -e /tmp/eet-clip-finished ]] && break; sleep 0.5; done
sleep 1.5
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
trap - EXIT
wait "$TEST"   # fails the script if the test failed

SECS=$(mdls -raw -name kMDItemDurationSeconds "$RAW" 2>/dev/null || echo "?")
echo "  recorded $RAW  (${SECS}s)"
# Never overwrite: if the name is taken, save as _v2, _v3, …
DEST="$OUT_DIR/$OUTNAME"; N=2
while [[ -e "$DEST" ]]; do DEST="$OUT_DIR/${OUTNAME%.mov}_v$N.mov"; N=$((N + 1)); done
mv -n "$RAW" "$DEST" && echo "  saved   $DEST"
