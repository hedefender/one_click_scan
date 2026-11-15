#!/usr/bin/env bash
# Runs EVERY file of integration_test/ on the Claude Code emulator, one after
# the other, each with the runner it needs, and prints a summary at the end
# (Phase 6.6, audit A1-007). It runs whole before every validation of a phase
# (see CLAUDE.md).
#
#   tool/run_all_integration.sh <device-id> [test-file ...]
#   tool/run_all_integration.sh emulator-5554
#   tool/run_all_integration.sh emulator-5554 integration_test/mail_flow_test.dart
#
# With test files after the device, only those run (a partial re-run); without
# them, all of `integration_test/*_test.dart` plus the release smoke test (R8)
# of tool/run_ocr_release_smoke.sh.
#
# Which runner a file gets (a new file gets the plain one):
#   mail_flow_test, one_click_flow_test   tool/run_mail_integration_test.sh (SMTP server on the PC)
#   pdf_flow_test, crop_flow_test         tool/run_pdf_integration_test.sh  (pulls the PDFs)
#   screenshots_test                      tool/run_screenshots.sh
#   all the others                        tool/run_integration_test.sh
#
# Disk: every install of the debug APK leaves about 200 MB that only a reboot of
# the emulator frees. So the app is uninstalled before each file and the
# emulator is rebooted every REBOOT_EVERY files (default 2), and once more, with
# one retry, when a run fails with INSTALL_FAILED_INSUFFICIENT_STORAGE. Only the
# Claude Code emulator is ever touched (the AVD name is checked before any
# command, and before the emulator is killed). One file that fails never stops
# the others. The exit code is not 0 when anything failed.
#
# Logs: build/integration_logs/<time>/<test>.log (build/ is ignored by git).
set -u
export MSYS_NO_PATHCONV=1

PACKAGE="io.github.hedefender.simpledocscan"
EXPECTED_AVD="Claude_Code_Test"
REBOOT_EVERY="${REBOOT_EVERY:-2}"
FILE_TIMEOUT="${FILE_TIMEOUT:-2700}" # seconds per file

if [ $# -lt 1 ]; then
  echo "usage: $0 <device-id> [test-file ...]" >&2
  exit 2
fi
DEVICE="$1"
shift

avd_name() {
  adb -s "$DEVICE" emu avd name 2>/dev/null | head -n 1 | tr -d '\r'
}

if [ "$(avd_name)" != "$EXPECTED_AVD" ]; then
  echo "Refusing to run: $DEVICE is '$(avd_name)', not '$EXPECTED_AVD'." >&2
  exit 3
fi

PORT="${DEVICE#emulator-}"
case "$PORT" in
  ''|*[!0-9]*) echo "Device id must look like emulator-5554." >&2; exit 2 ;;
esac

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$LOCALAPPDATA/Android/Sdk}}"
EMULATOR="$SDK/emulator/emulator"
[ -x "$EMULATOR" ] || EMULATOR="$SDK/emulator/emulator.exe"

wait_for_boot() {
  for _ in $(seq 1 90); do
    if [ "$(adb -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; then
      sleep 5
      return 0
    fi
    sleep 5
  done
  return 1
}

reboot_emulator() {
  if [ "$(avd_name)" = "$EXPECTED_AVD" ]; then
    adb -s "$DEVICE" emu kill >/dev/null 2>&1
  fi
  sleep 10
  "$EMULATOR" -avd "$EXPECTED_AVD" -port "$PORT" -no-snapshot-load -no-audio \
    >/dev/null 2>&1 &
  if ! wait_for_boot; then
    echo "The emulator did not come back." >&2
    return 1
  fi
  if [ "$(avd_name)" != "$EXPECTED_AVD" ]; then
    echo "After the reboot $DEVICE is not '$EXPECTED_AVD'." >&2
    return 1
  fi
}

if [ $# -gt 0 ]; then
  FILES=("$@")
else
  FILES=()
  for f in integration_test/*_test.dart; do FILES+=("$f"); done
  FILES+=("release-smoke")
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
LOGS="build/integration_logs/$STAMP"
mkdir -p "$LOGS"

run_one() { # <file> <log>
  local file="$1" log="$2" name
  name="$(basename "$file" .dart)"
  case "$file" in
    release-smoke)
      timeout "$FILE_TIMEOUT" bash tool/run_ocr_release_smoke.sh "$DEVICE" >"$log" 2>&1 ;;
    */mail_flow_test.dart | */one_click_flow_test.dart)
      timeout "$FILE_TIMEOUT" bash tool/run_mail_integration_test.sh "$DEVICE" "$file" >"$log" 2>&1 ;;
    */pdf_flow_test.dart | */crop_flow_test.dart)
      timeout "$FILE_TIMEOUT" bash tool/run_pdf_integration_test.sh "$DEVICE" "$LOGS/pdf_$name" "$file" >"$log" 2>&1 ;;
    */screenshots_test.dart)
      timeout "$FILE_TIMEOUT" bash tool/run_screenshots.sh "$DEVICE" "$LOGS/screenshots" >"$log" 2>&1 ;;
    *)
      timeout "$FILE_TIMEOUT" bash tool/run_integration_test.sh "$DEVICE" "$file" >"$log" 2>&1 ;;
  esac
}

NAMES=()
RESULTS=()
SECONDS_USED=()
ok=0
bad=0
installs=0
TOTAL_START=$SECONDS

for file in "${FILES[@]}"; do
  name="$(basename "$file" .dart)"
  log="$LOGS/$name.log"
  echo "=== $name"

  if [ "$installs" -gt 0 ] && [ $((installs % REBOOT_EVERY)) -eq 0 ]; then
    echo "    rebooting the emulator (every $REBOOT_EVERY files)"
    reboot_emulator || echo "    (reboot failed, going on)"
  fi
  adb -s "$DEVICE" uninstall "$PACKAGE" >/dev/null 2>&1

  start=$SECONDS
  run_one "$file" "$log"
  status=$?
  if [ $status -ne 0 ] && grep -q "INSUFFICIENT_STORAGE" "$log"; then
    echo "    out of space on the emulator: reboot and one more try"
    if reboot_emulator; then
      adb -s "$DEVICE" uninstall "$PACKAGE" >/dev/null 2>&1
      installs=0
      run_one "$file" "$log"
      status=$?
    fi
  fi
  elapsed=$((SECONDS - start))
  installs=$((installs + 1))

  NAMES+=("$name")
  SECONDS_USED+=("$elapsed")
  if [ $status -eq 0 ]; then
    RESULTS+=("OK")
    ok=$((ok + 1))
  else
    RESULTS+=("FAILED($status)")
    bad=$((bad + 1))
  fi
  echo "    ${RESULTS[${#RESULTS[@]} - 1]} in ${elapsed}s"
done

adb -s "$DEVICE" uninstall "$PACKAGE" >/dev/null 2>&1

echo
echo "================ SUMMARY ($STAMP) ================"
for i in "${!NAMES[@]}"; do
  printf "%-28s %-12s %5ss\n" "${NAMES[$i]}" "${RESULTS[$i]}" "${SECONDS_USED[$i]}"
done
echo "-------------------------------------------------"
echo "green: $ok   red: $bad   total time: $((SECONDS - TOTAL_START))s"
echo "logs: $LOGS"
[ "$bad" -eq 0 ]
