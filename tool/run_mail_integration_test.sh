#!/usr/bin/env bash
# Runs the Phase 4 integration test of the mail layer on the Claude Code
# emulator, with no human help.
#
#   tool/run_mail_integration_test.sh <device-id> [test-file]
#   tool/run_mail_integration_test.sh emulator-5554
#   tool/run_mail_integration_test.sh emulator-5554 integration_test/one_click_flow_test.dart
#
# The test file defaults to the Phase 4 mail test; Phase 5 passes its own.
#
# It starts the test SMTP server of tool/smtp_test_server.dart on this
# computer (loopback only; the emulator reaches it as 10.0.2.2), passes its
# ports to the test, and stops it afterwards. Only invented accounts and
# passwords are used and nothing leaves this computer. Like the other runners
# it refuses to run on any device that is not the Claude Code emulator.
set -u
export MSYS_NO_PATHCONV=1

PACKAGE="com.example.one_click_scan"
EXPECTED_AVD="Claude_Code_Test"
SMTP_PORT=25251
CONTROL_PORT=25252

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 <device-id> [test-file]" >&2
  exit 2
fi
DEVICE="$1"
TEST="${2:-integration_test/mail_flow_test.dart}"

AVD="$(adb -s "$DEVICE" emu avd name 2>/dev/null | head -n 1 | tr -d '\r')"
if [ "$AVD" != "$EXPECTED_AVD" ]; then
  echo "Refusing to run: $DEVICE is '$AVD', not '$EXPECTED_AVD'." >&2
  exit 3
fi

LOG="$(mktemp)"
GRANTER=0
SERVER=0
dart tool/smtp_test_server.dart --smtp-port "$SMTP_PORT" \
  --control-port "$CONTROL_PORT" >"$LOG" 2>&1 &
SERVER=$!
GRANTER=0
trap 'kill $SERVER 2>/dev/null; kill $GRANTER 2>/dev/null; rm -f "$LOG"' EXIT

for _ in $(seq 1 60); do
  grep -q 'READY smtp=' "$LOG" && break
  sleep 1
done
if ! grep -q 'READY smtp=' "$LOG"; then
  echo "The test SMTP server did not start:" >&2
  cat "$LOG" >&2
  exit 4
fi
echo "$(grep -o 'READY smtp=.*' "$LOG")"

# The app is installed fresh by `flutter test`; give the camera permission
# right after it lands (the screen flow uses a fake camera, but the app asks).
(
  for _ in $(seq 1 240); do
    adb -s "$DEVICE" shell pm grant "$PACKAGE" android.permission.CAMERA \
      >/dev/null 2>&1
    sleep 0.5
  done
) &
GRANTER=$!

flutter test "$TEST" -d "$DEVICE" \
  --dart-define=MAIL_SMTP_PORT="$SMTP_PORT" \
  --dart-define=MAIL_CONTROL_PORT="$CONTROL_PORT"
