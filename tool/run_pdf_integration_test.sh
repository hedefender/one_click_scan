#!/usr/bin/env bash
# Runs the Phase 3 integration test (real OCR, real PDF writer) on the Claude
# Code emulator with no human help, and copies the PDFs it writes to the PC.
#
#   tool/run_pdf_integration_test.sh <device-id> [out-dir]
#   tool/run_pdf_integration_test.sh emulator-5554 build/pdf_it
#
# Like tool/run_integration_test.sh it refuses to run on any device that is not
# the Claude Code emulator and grants the CAMERA permission after the install.
# `flutter test` removes the app (and its files) when it ends, so the test
# copies each PDF to `files/pdf_it/` inside the app and this script reads that
# folder with `run-as` (debug build) every second while the test runs. The text of the
# PDFs is then checked on the PC with tool/check_pdf_text.py.
set -u
export MSYS_NO_PATHCONV=1

PACKAGE="com.example.one_click_scan"
EXPECTED_AVD="Claude_Code_Test"
REMOTE="files/pdf_it"   # inside the app (run-as; the test app is a debug build)

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 <device-id> [out-dir]" >&2
  exit 2
fi
DEVICE="$1"
OUT="${2:-build/pdf_it}"

AVD="$(adb -s "$DEVICE" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')"
if [ "$AVD" != "$EXPECTED_AVD" ]; then
  echo "Refusing to run: $DEVICE is '$AVD', not '$EXPECTED_AVD'." >&2
  exit 3
fi

mkdir -p "$OUT"
(
  for i in $(seq 1 3000); do
    if [ $((i % 10)) -eq 1 ]; then
      adb -s "$DEVICE" shell pm grant "$PACKAGE" android.permission.CAMERA \
        >/dev/null 2>&1
    fi
    for name in $(adb -s "$DEVICE" shell run-as "$PACKAGE" ls "$REMOTE" 2>/dev/null | tr -d '\r'); do
      adb -s "$DEVICE" exec-out run-as "$PACKAGE" cat "$REMOTE/$name" \
        > "$OUT/$name.part" 2>/dev/null
      # Keep only real PDFs (after the app is gone run-as prints an error).
      if [ "$(head -c 4 "$OUT/$name.part")" = "%PDF" ]; then
        mv "$OUT/$name.part" "$OUT/$name"
      else
        rm -f "$OUT/$name.part"
      fi
    done
    sleep 2
  done
) &
HELPER=$!
trap 'kill $HELPER 2>/dev/null' EXIT

flutter test integration_test/pdf_flow_test.dart -d "$DEVICE"
STATUS=$?
sleep 2
echo "PDFs pulled to $OUT:"
ls -l "$OUT"
exit $STATUS
