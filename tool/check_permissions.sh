#!/usr/bin/env bash
# Compares the permissions of a release APK with tool/allowed_permissions.txt
# (Phase 6.7, audit A1-003, ADR-035). It reads the APK, the product, not the
# source manifest: plugins add permissions at merge time (the microphone and the
# network state came that way).
#
#   tool/check_permissions.sh [apk]
#   tool/check_permissions.sh build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
#
# Default APK: build/app/outputs/flutter-apk/app-release.apk. Exit 0 when the
# permissions are exactly the allowed ones, 1 otherwise (with the names), 2 when
# the APK or aapt2 cannot be found. Called by tool/run_ocr_release_smoke.sh, so
# tool/run_all_integration.sh runs it with the release smoke test.
set -u

APK="${1:-build/app/outputs/flutter-apk/app-release.apk}"
LIST="$(dirname "$0")/allowed_permissions.txt"

if [ ! -f "$APK" ]; then
  echo "check_permissions: no APK at $APK" >&2
  exit 2
fi

SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$SDK" ] && [ -n "${LOCALAPPDATA:-}" ]; then
  SDK="$(cygpath -u "$LOCALAPPDATA" 2>/dev/null || echo "$LOCALAPPDATA")/Android/Sdk"
fi
AAPT2=""
for dir in $(ls -d "$SDK"/build-tools/* 2>/dev/null | sort -V -r); do
  for name in aapt2 aapt2.exe; do
    if [ -x "$dir/$name" ]; then AAPT2="$dir/$name"; break 2; fi
  done
done
if [ -z "$AAPT2" ]; then
  echo "check_permissions: aapt2 not found under $SDK/build-tools" >&2
  exit 2
fi

DUMP="$("$AAPT2" dump permissions "$APK" 2>&1)" || {
  echo "check_permissions: aapt2 failed: $DUMP" >&2
  exit 2
}
APP_ID="$(printf '%s\n' "$DUMP" | sed -n 's/^package: //p' | head -n 1 | tr -d '\r')"

FOUND="$(printf '%s\n' "$DUMP" | tr -d '\r' \
  | sed -n "s/^uses-permission[a-z-]*: name='\([^']*\)'.*/\1/p" | sort -u)"
ALLOWED="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$LIST" \
  | sed "s/\${applicationId}/$APP_ID/g" | sort -u)"

UNKNOWN="$(comm -23 <(printf '%s\n' "$FOUND") <(printf '%s\n' "$ALLOWED"))"
MISSING="$(comm -13 <(printf '%s\n' "$FOUND") <(printf '%s\n' "$ALLOWED"))"

if [ -n "$UNKNOWN" ] || [ -n "$MISSING" ]; then
  echo "check_permissions: FAILED for $APK" >&2
  if [ -n "$UNKNOWN" ]; then
    echo "Permissions in the APK that tool/allowed_permissions.txt does not allow:" >&2
    printf '  %s\n' $UNKNOWN >&2
    echo "Remove them with tools:node=\"remove\" in AndroidManifest.xml, or, if the" >&2
    echo "app really needs one, add it to the list with the reason (ADR-035)." >&2
  fi
  if [ -n "$MISSING" ]; then
    echo "Allowed permissions that the APK does not have:" >&2
    printf '  %s\n' $MISSING >&2
  fi
  exit 1
fi
echo "check_permissions: OK, $(printf '%s\n' "$FOUND" | wc -l | tr -d ' ') permissions, all allowed:"
printf '  %s\n' $FOUND
