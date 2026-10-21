# Phase 1.2: manual validation (performed by the user)

App icon, splash screen and the names of the Gallery copies. Use your own
emulator or phone.

1. **Icon.** Install the new APK. The launcher icon is the new one (camera,
   paper plane, PDF on the dark blue), not the Flutter "F". The symbol is not
   cut. If the launcher lets you change the icon shape, try circle, rounded
   square and squircle.
2. **Splash.** Force-stop the app and start it from the launcher. The splash
   shows the original icon (with its rounded frame) in the middle on the same
   dark blue, with no cut corners and no "F".
3. **Gallery off.** Switch off in Settings. Scan: no picture appears in the
   Gallery, and `./pictures/` has the files.
4. **Gallery on.** Switch on. Scan one page: the Gallery shows
   `scan_<today>_01.jpg` (for example `scan_2026-10-22_01.jpg`; in Google Photos
   open the picture details to see the name). Scan two pages: `_02` and `_03`.
5. **Originals.** `./pictures/` keeps the files under their own names
   (`<date>_<time>_<n>.jpg`), unchanged. The Gallery switch does not rename
   them.
6. **Dark mode.** Switch the phone to dark mode: icon and splash look the same
   (the splash background is the same dark blue in both modes).
7. **Next day.** The first Gallery copy after midnight is `_01` again.
8. **Real phone (arm64).** Same steps 1 to 6.
   - Build: `flutter build apk --debug --target-platform android-arm64`
   - APK: `build\app\outputs\flutter-apk\app-debug.apk`

Not checked by Claude: Android 7.x (legacy icon), Android 8 to 11 splash
(window background), themed (monochrome) icons.

## For Claude Code

- The generated files come from `dart run tool/generate_branding.dart`
  (needs the dev dependency `image`). Do not edit the PNGs by hand.
- The Gallery name test on the emulator:
  `tool/run_integration_test.sh <your-device> integration_test/gallery_copy_test.dart`,
  then `adb -s <your-device> shell "content query --uri
  content://media/external/images/media --projection
  _display_name:relative_path --where \"_display_name LIKE 'scan_%'\""` shows
  `scan_2000-01-01_01.jpg` under `Pictures/`.
- Splash screenshots: start without waiting (`am start` without `-W`) and run
  `screencap` right after, in one `adb shell` call.
