#!/usr/bin/env bash
# Runs one integration test on the Claude Code emulator, with no human help.
#
#   tool/run_integration_test.sh <device-id> <test-file>
#   tool/run_integration_test.sh emulator-5554 integration_test/camera_smoke_test.dart
#
# Why it exists: `flutter test` installs the app fresh (and removes it again)
# on every run, and a fresh install has no CAMERA permission, so the system
# dialog appears and nobody presses it. This script keeps granting the
# permission with adb while the test starts, and refuses to run on any device
# that is not the Claude Code emulator (the user's emulator is never touched).
set -u

PACKAGE="com.example.one_click_scan"
EXPECTED_AVD="Claude_Code_Test"

if [ $# -ne 2 ]; then
  echo "usage: $0 <device-id> <test-file>" >&2
  exit 2
fi
DEVICE="$1"
TEST="$2"

AVD="$(adb -s "$DEVICE" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')"
if [ "$AVD" != "$EXPECTED_AVD" ]; then
  echo "Refusing to run: $DEVICE is '$AVD', not '$EXPECTED_AVD'." >&2
  exit 3
fi

# Grant right after the install lands, before the test opens the camera.
(
  for _ in $(seq 1 240); do
    adb -s "$DEVICE" shell pm grant "$PACKAGE" android.permission.CAMERA \
      >/dev/null 2>&1
    sleep 0.5
  done
) &
GRANTER=$!
trap 'kill $GRANTER 2>/dev/null' EXIT

flutter test "$TEST" -d "$DEVICE"
