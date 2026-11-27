#!/usr/bin/env bash
# Captures the Apple Watch screenshots straight from the watch simulator (no xcodebuild test:
# that clones the simulator). The watch app's DEBUG screenshot mode shows a frozen engine state,
# and -screenshotScroll starts the scroll view scrolled, since simctl can't turn the Digital Crown.
#
# Writes PNGs to a scratch directory first, then moves them into OUT_DIR WITHOUT overwriting: files
# another process created there can't always be replaced, and an existing capture is never clobbered.
#
# Usage: scripts/capture_watch.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH_NAME="${WATCH_NAME:-Apple Watch Ultra 4 (49mm)}"      # largest current size: 422 x 514
OUT_DIR="${OUT_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/ClaudeCoWork/Personal-App-Development/EET/raw}"
SCRATCH="${SCRATCH:-/tmp/eet-watch/out}"
DERIVED="${DERIVED:-/tmp/eet-watch-dd}"
LANG_CODE=en
EXPECT="422x514"

# file stem | scene | scroll offset (points)
CAPTURES=(
  "02_manualSet|manualSet|60"            # workout screen: rep-based set, Hold: Reps Complete
  "05_restLog|restLog|170"               # rest countdown with "Then: …"
  "04_timedSuperset|timedSuperset|170"   # Timed Superset "7:42 left" line
  "07_recap|recap|0"                     # recap, top
  "07b_recapStats|recap|150"             # recap, stats and Done
)

echo "▶︎ building the watch app (Debug)"
xcodebuild -project "$REPO/ExerciseTimer.xcodeproj" -scheme ExpandableExerciseTimerWatch -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO -quiet build
APP="$DERIVED/Build/Products/Debug-watchsimulator/ExpandableExerciseTimerWatch.app"
BID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; print([d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['name']=='$WATCH_NAME'][-1])")
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
# watchOS simulators don't support status_bar override, so the clock shows the simulator's own time.
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

rm -rf "$SCRATCH"; mkdir -p "$SCRATCH" "$OUT_DIR"

for entry in "${CAPTURES[@]}"; do
  IFS='|' read -r STEM SCENE SCROLL <<<"$entry"
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BID" -screenshotMode -screenshotScene "$SCENE" -screenshotScroll "$SCROLL" >/dev/null
  sleep 4   # launch, load the scene, scroll
  xcrun simctl io "$UDID" screenshot "$SCRATCH/watch_${LANG_CODE}_${STEM}.png" >/dev/null 2>&1
done

# simctl screenshots are RGBA; App Store Connect rejects alpha. Drop it (after checking every
# pixel is opaque, so nothing visible changes), then report sizes.
python3 -I - "$SCRATCH" <<'PY'
import pathlib, struct, sys, zlib

def read_png(path):
    d = path.read_bytes(); pos = 8; idat = b""; hdr = None
    while pos < len(d):
        n, t = struct.unpack(">I4s", d[pos:pos + 8])
        if t == b"IHDR": hdr = struct.unpack(">IIBBBBB", d[pos + 8:pos + 21])
        if t == b"IDAT": idat += d[pos + 8:pos + 8 + n]
        pos += 12 + n
    w, h, depth, ctype, *_ = hdr
    assert depth == 8 and ctype in (2, 6), (depth, ctype)
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat); stride = w * bpp
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]; line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0; b = prev[i]; c = prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(line); prev = line
    return w, h, bpp, rows

def write_rgb(path, w, h, rows):
    def chunk(t, data): return struct.pack(">I", len(data)) + t + data + struct.pack(">I", zlib.crc32(t + data) & 0xFFFFFFFF)
    body = b"".join(b"\x00" + bytes(r) for r in rows)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(body, 9)) + chunk(b"IEND", b""))

for p in sorted(pathlib.Path(sys.argv[1]).glob("*.png")):
    w, h, bpp, rows = read_png(p)
    if bpp == 4:
        assert all(r[3::4].count(255) == w for r in rows), f"{p.name} has transparent pixels"
        rows = [bytearray(b for i, b in enumerate(r) if i % 4 != 3) for r in rows]
        write_rgb(p, w, h, rows)
    print(f"  {p.name}  {w}x{h}  (alpha removed)" if bpp == 4 else f"  {p.name}  {w}x{h}")
PY

# Move into place without overwriting anything that is already there.
echo "▶︎ moving into $OUT_DIR (no overwrite)"
for f in "$SCRATCH"/*.png; do
  name="$(basename "$f")"
  if [[ -e "$OUT_DIR/$name" ]]; then
    echo "  skipped $name: already exists in OUT_DIR (left untouched; scratch copy kept at $f)"
  else
    mv -n "$f" "$OUT_DIR/$name" && echo "  saved   $name"
  fi
done

BAD=0
for f in "$OUT_DIR"/watch_${LANG_CODE}_*.png; do
  [[ -e "$f" ]] || continue
  got=$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w"x"h}')
  alpha=$(sips -g hasAlpha "$f" | awk '/hasAlpha/{print $2}')
  [[ "$got" == "$EXPECT" && "$alpha" == "no" ]] || { echo "⚠︎ $(basename "$f"): $got, alpha=$alpha (expected $EXPECT, no alpha)"; BAD=1; }
done
[[ $BAD -eq 0 ]] && echo "All watch captures are $EXPECT with no alpha channel."
echo "Done."
