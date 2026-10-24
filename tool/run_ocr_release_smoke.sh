#!/usr/bin/env bash
# Release smoke test of the OCR (R8 on) on the Claude Code emulator.
#
#   tool/run_ocr_release_smoke.sh <device-id>
#
# `flutter test` and `flutter drive` cannot run in release mode, so this builds
# a release APK whose entry point is tool/ocr_release_smoke_main.dart
# (it runs the OCR smoke, opens and closes the real camera, uses
# shared_preferences, and prints one OCRSMOKE line), installs it
# on the emulator, starts it and waits for the line in logcat. It also checks
# that R8 really ran and kept the ONNX Runtime classes. Refuses to touch any
# device that is not the Claude Code emulator.
set -u

PACKAGE="com.example.one_click_scan"
EXPECTED_AVD="Claude_Code_Test"

if [ $# -ne 1 ]; then
  echo "usage: $0 <device-id>" >&2
  exit 2
fi
DEVICE="$1"

AVD="$(adb -s "$DEVICE" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')"
if [ "$AVD" != "$EXPECTED_AVD" ]; then
  echo "Refusing to run: $DEVICE is '$AVD', not '$EXPECTED_AVD'." >&2
  exit 3
fi

ABI="$(adb -s "$DEVICE" shell getprop ro.product.cpu.abi | tr -d '\r')"
case "$ABI" in
  x86_64) PLATFORM=android-x64 ;;
  arm64-v8a) PLATFORM=android-arm64 ;;
  *) echo "Unexpected ABI $ABI" >&2; exit 4 ;;
esac

flutter build apk --release --target-platform "$PLATFORM" \
  -t tool/ocr_release_smoke_main.dart || exit 5

MAPPING="build/app/outputs/mapping/release/mapping.txt"
if [ -f "$MAPPING" ]; then
  echo "R8 ran: $MAPPING ($(wc -l < "$MAPPING") lines)"
  if grep -q '^ai.onnxruntime.OrtSession -> ai.onnxruntime.OrtSession:' "$MAPPING"; then
    echo "R8 kept ai.onnxruntime.OrtSession under its own name."
  else
    echo "WARNING: ai.onnxruntime.OrtSession is not kept as is in the mapping." >&2
  fi
else
  echo "WARNING: no R8 mapping file; minification may be off." >&2
fi

adb -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-release.apk || exit 6
adb -s "$DEVICE" shell pm grant "$PACKAGE" android.permission.CAMERA
adb -s "$DEVICE" logcat -c
adb -s "$DEVICE" shell am start -n "$PACKAGE/.MainActivity" >/dev/null

for _ in $(seq 1 90); do
  LINE="$(adb -s "$DEVICE" logcat -d -s flutter 2>/dev/null | grep -a 'OCRSMOKE' | tail -n 1)"
  if [ -n "$LINE" ]; then
    echo "$LINE"
    case "$LINE" in
      *"OCRSMOKE ok"*) exit 0 ;;
      *) exit 1 ;;
    esac
  fi
  sleep 2
done
echo "No OCRSMOKE line within 180 s; crash? last log:" >&2
adb -s "$DEVICE" logcat -d -t 40 >&2
exit 7
