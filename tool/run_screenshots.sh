#!/usr/bin/env bash
# Takes the screenshots of every screen, light and dark theme, in Greek, on the
# Claude Code emulator, and copies them to build/screenshots/light and
# build/screenshots/dark (build/ is ignored by git).
#
#   tool/run_screenshots.sh <device-id> [out-dir] [folder-prefix]
#   tool/run_screenshots.sh emulator-5554
#   tool/run_screenshots.sh emulator-5554 build/screenshots after_   (Phase 6.4:
#   build/screenshots/after_light and build/screenshots/after_dark)
#   SYSTEM_COLORS=false tool/run_screenshots.sh <device> build/screenshots after_ 
#   keeps the fallback palettes (without it the emulator's system colours show).
#
# Only invented data: integration_test/screenshots_test.dart uses the fakes of
# the widget tests (a drawn receipt, demo@example.test, nothing is sent). The
# pictures are of the Flutter surface only (no Android status bar). Like the
# other runners it refuses any device that is not the Claude Code emulator and
# grants the CAMERA permission after the install. The test writes the pictures
# into files/shots of the app (debug build) and this script reads that folder
# with `run-as` while the test runs, because `flutter test` removes the app
# when it ends.
set -u
export MSYS_NO_PATHCONV=1

PACKAGE="io.github.hedefender.simpledocscan"
EXPECTED_AVD="Claude_Code_Test"
REMOTE="files/shots"

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
  echo "usage: $0 <device-id> [out-dir] [folder-prefix]" >&2
  exit 2
fi
DEVICE="$1"
OUT="${2:-build/screenshots}"
PREFIX="${3:-}"

AVD="$(adb -s "$DEVICE" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')"
if [ "$AVD" != "$EXPECTED_AVD" ]; then
  echo "Refusing to run: $DEVICE is '$AVD', not '$EXPECTED_AVD'." >&2
  exit 3
fi

mkdir -p "$OUT/${PREFIX}light" "$OUT/${PREFIX}dark"
(
  for i in $(seq 1 3000); do
    if [ $((i % 10)) -eq 1 ]; then
      adb -s "$DEVICE" shell pm grant "$PACKAGE" android.permission.CAMERA \
        >/dev/null 2>&1
    fi
    for name in $(adb -s "$DEVICE" shell run-as "$PACKAGE" ls "$REMOTE" 2>/dev/null | tr -d '\r'); do
      case "$name" in
        light_*.png) dir="${PREFIX}light"; target="${name#light_}" ;;
        dark_*.png) dir="${PREFIX}dark"; target="${name#dark_}" ;;
        *) continue ;;
      esac
      [ -f "$OUT/$dir/$target" ] && continue
      adb -s "$DEVICE" exec-out run-as "$PACKAGE" cat "$REMOTE/$name" \
        > "$OUT/$dir/$target.part" 2>/dev/null
      # Keep only real PNGs (after the app is gone run-as prints an error).
      if [ "$(head -c 4 "$OUT/$dir/$target.part" | tail -c 3)" = "PNG" ]; then
        mv "$OUT/$dir/$target.part" "$OUT/$dir/$target"
      else
        rm -f "$OUT/$dir/$target.part"
      fi
    done
    sleep 2
  done
) &
HELPER=$!
trap 'kill $HELPER 2>/dev/null' EXIT

flutter test integration_test/screenshots_test.dart -d "$DEVICE" \
  --dart-define=SYSTEM_COLORS="${SYSTEM_COLORS:-true}"
STATUS=$?
sleep 3
echo "Screenshots pulled to $OUT:"
ls "$OUT/${PREFIX}light" | wc -l
ls "$OUT/${PREFIX}dark" | wc -l
exit $STATUS
