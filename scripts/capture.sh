#!/usr/bin/env bash
# Captures the 3.0 App Store screenshots: runs ScreenshotTests on each simulator, then the Mac
# window captures, and writes PNGs named <device>_<lang>_<NN>_<scene>.png into OUT_DIR.
#
# Usage:  scripts/capture.sh                 all devices
#         scripts/capture.sh iphone69 ipad13 only these tags (iphone69 duo_outer duo_inner ipad13 mac)
#
# The app must be a DEBUG build: screenshot mode is compiled out of Release.
set -euo pipefail

# ---------------- CONFIG ----------------
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ARGS=(-project "$REPO/ExerciseTimer.xcodeproj")
SCHEME="ExerciseTimer"
UITEST_CLASS="ExerciseTimerUITests/ScreenshotTests"
LANGS=(en)
OUT_DIR="${OUT_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/ClaudeCoWork/Personal-App-Development/EET/raw}"
WORK_DIR="${WORK_DIR:-/tmp/eet-capture}"

# scene number -> test method / scene name (see ScreenshotTests.swift). Plain functions, because
# macOS ships bash 3.2, which has no associative arrays.
test_for() {
  case "$1" in
    01) echo test01_plan ;;          02) echo test02_manualSet ;;   03) echo test03_superset ;;
    04) echo test04_timedSuperset ;; 05) echo test05_restLog ;;     06) echo test06_overview ;;
    07) echo test07_recap ;;         08) echo test08_routines ;;    09) echo test09_timer ;;
    10) echo test10_createPlan ;;
  esac
}
scene_for() { test_for "$1" | sed -E 's/^test[0-9]+_//'; }

# tag | simulator name | orientation | fold state the Duo must be in ("-" = none) | scenes
# Use the exact simulator names shown in Device Hub.
DEVICES=(
  "iphone69|iPhone 17 Pro Max|portrait|-|01 02 03 04 05 06 07 08 09 10"
  "duo_outer|iPhone Duo|portrait|folded (outer display)|01 02 03 04 05 07"
  "duo_inner|iPhone Duo|landscape|unfolded (inner display)|01 02 03 05 06 07"
  "ipad13|iPad Pro 13-inch (M5)|portrait|-|01 02 06 07 08"
)
# Mac: window captures of these scenes (screencapture -l), window sized for 2880x1800 on a Retina display.
MAC_SCENES="01 02 06 07"
MAC_WINDOW_POINTS="1440x900"
# Expected pixel size per tag, checked after export (App Store Connect screenshot specifications).
expect_for() {
  case "$1" in
    iphone69)  echo 1320x2868 ;;   # 6.9": 1260x2736, 1290x2796 and 1320x2868 are all accepted
    duo_outer) echo 1398x2034 ;;
    duo_inner) echo 2853x2007 ;;   # the plan also allows 2670x1878 raw
    ipad13)    echo 2064x2752 ;;
    mac)       echo 2880x1800 ;;
  esac
}
# ----------------------------------------

WANT=("$@")
wanted() { [[ ${#WANT[@]} -eq 0 ]] && return 0; local t; for t in "${WANT[@]}"; do [[ "$t" == "$1" ]] && return 0; done; return 1; }

mkdir -p "$OUT_DIR" "$WORK_DIR"
SIZE_PROBLEMS=()

check_size() {  # file tag
  local got want; want="$(expect_for "$2")"
  got=$(sips -g pixelWidth -g pixelHeight "$1" | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w"x"h}')
  echo "  $(basename "$1")  $got"
  if [[ -n "$want" && "$got" != "$want" ]]; then SIZE_PROBLEMS+=("$(basename "$1"): got $got, expected $want"); fi
  # A black frame (e.g. the Duo's inner display while folded) compresses to almost nothing.
  if [[ $(stat -f%z "$1") -lt 40000 ]]; then SIZE_PROBLEMS+=("$(basename "$1"): looks blank ($(stat -f%z "$1") bytes)"); fi
}

run_simulator() {
  local TAG="$1" NAME="$2" ORIENT="$3" FOLD="$4" SCENES="$5"
  local UDID
  UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; print([d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['name']=='$NAME'][-1])")
  xcrun simctl boot "$UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
  xcrun simctl status_bar "$UDID" override --time "9:41" \
    --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null \
    || echo "note: status bar override not available for $NAME"

  # Duo: set the fold state in Device Hub before capturing that display.
  if [[ "$FOLD" != "-" ]]; then
    read -r -p "Set '$NAME' to $FOLD in Device Hub, then press Return… " _ || echo "(no terminal: continuing; the size check below flags a wrong fold state)"
  fi

  local ONLY=() n
  for n in $SCENES; do ONLY+=(-only-testing:"$UITEST_CLASS/$(test_for "$n")"); done

  for LANG_CODE in "${LANGS[@]}"; do
    local RESULT="$WORK_DIR/${TAG}_${LANG_CODE}.xcresult" EXPORT="$WORK_DIR/${TAG}_${LANG_CODE}_export"
    rm -rf "$RESULT" "$EXPORT"; mkdir -p "$EXPORT"
    echo "▶︎ $TAG ($NAME) [$LANG_CODE] $ORIENT scenes: $SCENES"

    TEST_RUNNER_SCREENSHOT_DEVICE="$TAG" \
    TEST_RUNNER_SCREENSHOT_LANG="$LANG_CODE" \
    TEST_RUNNER_SCREENSHOT_ORIENTATION="$ORIENT" \
    xcodebuild test "${PROJECT_ARGS[@]}" -scheme "$SCHEME" -configuration Debug \
      -destination "platform=iOS Simulator,id=$UDID" \
      "${ONLY[@]}" -resultBundlePath "$RESULT" -quiet

    xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EXPORT"

    # Attachments are named NN_scene; export them as <device>_<lang>_<NN>_<scene>.png.
    python3 -I - "$EXPORT" "$OUT_DIR" "$TAG" "$LANG_CODE" <<'PY'
import json, pathlib, re, shutil, sys
src, dst, tag, lang = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
for test in json.loads((src / "manifest.json").read_text()):
    for a in test.get("attachments", []):
        name = a.get("suggestedHumanReadableName", a["exportedFileName"])
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(?=\.\w+$)", "", name)   # strip index/UUID suffix
        stem = pathlib.Path(name).stem
        if not re.match(r"^\d{2}[a-z]?_", stem):
            continue                                                  # ignore anything that isn't a capture
        out = dst / f"{tag}_{lang}_{stem}.png"
        shutil.copy(src / a["exportedFileName"], out)
        print(out)
PY
  done


  for f in "$OUT_DIR/${TAG}_"*.png; do [[ -e "$f" ]] && check_size "$f" "$TAG"; done
}

run_mac() {
  local TAG=mac
  echo "▶︎ mac scenes: $MAC_SCENES"
  local DD="$WORK_DIR/mac-dd"
  xcodebuild "${PROJECT_ARGS[@]}" -scheme "$SCHEME" -configuration Debug \
    -destination "platform=macOS" -derivedDataPath "$DD" -quiet build
  local APP BIN
  APP=$(find "$DD/Build/Products/Debug" -maxdepth 1 -name "*.app" | head -1)
  BIN="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$APP/Contents/Info.plist")"

  local n NAME_OF PID WID W H
  # Needs Screen Recording (screencapture) and Accessibility (window sizing) permission for the
  # app running this script, and an unlocked display.
  screencapture -x "$WORK_DIR/.probe.png" 2>/dev/null || { echo "Mac capture needs Screen Recording permission and an unlocked display; skipping."; return 1; }
  trap 'pkill -x "$(basename "$BIN")" 2>/dev/null || true' RETURN
  W=${MAC_WINDOW_POINTS%x*}; H=${MAC_WINDOW_POINTS#*x}
  for n in $MAC_SCENES; do
    NAME_OF="$(scene_for "$n")"
    pkill -x "$(basename "$BIN")" 2>/dev/null || true
    "$BIN" -screenshotMode -screenshotScene "$NAME_OF" -AppleLanguages "(en)" >/dev/null 2>&1 &
    PID=$!
    sleep 4
    # Size and place the window so a window capture is exactly 2880x1800 on a Retina display.
    osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set {position, size} of window 1 to {{0, 40}, {$W, $H}}" || true
    sleep 2
    WID=$(swift "$REPO/scripts/windowid.swift" "$PID")
    screencapture -o -x -l"$WID" "$OUT_DIR/${TAG}_en_${n}_${NAME_OF}.png"
    kill "$PID" 2>/dev/null || true
    check_size "$OUT_DIR/${TAG}_en_${n}_${NAME_OF}.png" "$TAG"
  done
}

for entry in "${DEVICES[@]}"; do
  IFS='|' read -r TAG NAME ORIENT FOLD SCENES <<<"$entry"
  wanted "$TAG" && run_simulator "$TAG" "$NAME" "$ORIENT" "$FOLD" "$SCENES"
done
wanted mac && run_mac

echo
if [[ ${#SIZE_PROBLEMS[@]} -gt 0 ]]; then
  echo "⚠︎ Files that don't match the expected size:"; printf '  %s\n' "${SIZE_PROBLEMS[@]}"
else
  echo "All captured files match their expected pixel sizes."
fi
echo "Done. Raw captures are in $OUT_DIR"
