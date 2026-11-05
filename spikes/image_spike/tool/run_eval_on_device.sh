#!/usr/bin/env bash
# Builds the evaluation as a release APK, installs it on the Claude Code
# emulator, runs it and saves the IMGEVAL lines from logcat.
#
#   tool/run_eval_on_device.sh <device-id>
#   ENTRY=lib/ocr_eval_main.dart MARK=OCREVAL TRIES=600 tool/run_eval_on_device.sh <device-id>
#
# Release mode on purpose: `flutter test` runs in debug (JIT), which makes
# Dart timings meaningless. Refuses any device that is not the Claude Code
# emulator (the user's emulator and phone are never touched).
set -u
PACKAGE="com.example.image_spike"
ENTRY="${ENTRY:-lib/eval_main.dart}"
MARK="${MARK:-IMGEVAL}"
TRIES="${TRIES:-240}"
EXPECTED_AVD="Claude_Code_Test"
if [ $# -ne 1 ]; then echo "usage: $0 <device-id>" >&2; exit 2; fi
DEVICE="$1"
AVD="$(adb -s "$DEVICE" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')"
if [ "$AVD" != "$EXPECTED_AVD" ]; then
  echo "Refusing to run: $DEVICE is '$AVD', not '$EXPECTED_AVD'." >&2; exit 3
fi
ABI="$(adb -s "$DEVICE" shell getprop ro.product.cpu.abi | tr -d '\r')"
case "$ABI" in
  x86_64) PLATFORM=android-x64 ;;
  arm64-v8a) PLATFORM=android-arm64 ;;
  *) echo "Unexpected ABI $ABI" >&2; exit 4 ;;
esac
flutter build apk --release --target-platform "$PLATFORM" -t "$ENTRY" || exit 5
adb -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-release.apk || exit 6
adb -s "$DEVICE" logcat -G 4M >/dev/null 2>&1
adb -s "$DEVICE" logcat -c
adb -s "$DEVICE" shell am start -n "$PACKAGE/.MainActivity" >/dev/null
mkdir -p build/eval
OUT="build/eval/${MARK}_${ABI}.log"
for _ in $(seq 1 "$TRIES"); do
  adb -s "$DEVICE" logcat -d -s flutter 2>/dev/null | grep -a "$MARK" > "$OUT"
  if grep -aq "$MARK done" "$OUT"; then echo "done: $OUT"; exit 0; fi
  if grep -aq "$MARK FAILED" "$OUT"; then cat "$OUT" >&2; exit 1; fi
  sleep 3
done
echo "No $MARK done in time; last log:" >&2
adb -s "$DEVICE" logcat -d -t 40 >&2
exit 7
