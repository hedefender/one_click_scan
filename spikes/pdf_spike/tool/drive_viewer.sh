#!/usr/bin/env bash
# Emulator driver (Claude_Code_Test only): opens a PDF of the spike in the
# emulator's PDF viewer, long-presses the payment code, taps Copy, then lets the
# spike read the clipboard and compare it with the invented code.
#   tool/drive_viewer.sh <device> <pdf file name> <expected code> <x> <y> <screenshot dir>
set -u
export MSYS_NO_PATHCONV=1
TMPF="$(cygpath -m "$(mktemp)" 2>/dev/null || mktemp)"
DEV="$1"; NAME="$2"; WANT="$3"; X="$4"; Y="$5"; SHOTS="$6"
PKG=com.example.pdf_spike
DIR=/sdcard/Android/data/$PKG/files/out
AVD="$(adb -s "$DEV" emu avd name | head -n 1 | tr -d '\r')"
[ "$AVD" = "Claude_Code_Test" ] || { echo "refusing: $AVD"; exit 3; }

put() { echo "$1" > "$TMPF"; adb -s "$DEV" push "$TMPF" $DIR/command.txt >/dev/null; }

adb -s "$DEV" shell settings put system screen_off_timeout 1800000
adb -s "$DEV" shell input keyevent KEYCODE_WAKEUP
adb -s "$DEV" shell wm dismiss-keyguard
adb -s "$DEV" shell am force-stop $PKG
adb -s "$DEV" shell am force-stop com.google.android.apps.docs
adb -s "$DEV" shell input keyevent KEYCODE_HOME
put "clear"
adb -s "$DEV" shell am start -n $PKG/.MainActivity >/dev/null
sleep 5
adb -s "$DEV" shell am force-stop $PKG
put "open $NAME"
adb -s "$DEV" logcat -c
adb -s "$DEV" shell am start -n $PKG/.MainActivity >/dev/null
sleep 8
MSYS_NO_PATHCONV=1 adb -s "$DEV" exec-out screencap -p > "$SHOTS/${NAME%.pdf}_open.png"
adb -s "$DEV" shell input swipe "$X" "$Y" "$X" "$Y" 1200
sleep 2
MSYS_NO_PATHCONV=1 adb -s "$DEV" exec-out screencap -p > "$SHOTS/${NAME%.pdf}_sel.png"
adb -s "$DEV" shell input tap 1014 146   # Copy icon of the selection bar
sleep 1
put "clip $WANT"
adb -s "$DEV" shell am force-stop $PKG
adb -s "$DEV" logcat -c
adb -s "$DEV" shell am start -n $PKG/.MainActivity >/dev/null
sleep 7
echo "$NAME: $(adb -s "$DEV" logcat -d -s flutter | grep -a 'PDFSPIKE clip' | tail -1 | cut -c40-220)"
