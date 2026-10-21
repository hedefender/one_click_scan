# Phase 1: manual validation (performed by the user)

Use your own emulator or phone. Claude Code never touches your emulator.
Items 3 to 9 need the real folder picker, so they cannot be automated.

```
flutter pub get
flutter analyze
flutter test
flutter run
```

1. **Camera opens.** On home tap SCAN & SEND: the camera opens. The first time, Android asks for the camera permission.
2. **Permission denied.** Deny it: a clear message appears with `Try again` and `App settings`. Allow it in the system settings and come back: the camera starts by itself.
3. **Single page.** Take one photo. The result screen lists `YYYY-MM-DD_HH-MM-SS_1.jpg`. In your folder (Files app or Explorer) it is in `pictures/`.
4. **Multi page.** Switch to "Multi page", take 3 photos (thumbnails and the page count appear), delete the last one, tap `Done`. Two files `_1` and `_2` with the same stem are in `pictures/`.
5. **Cancel.** In Multi page take two photos and press back, then `Discard`. Then do it again and kill the app from the recent apps instead. In both cases nothing new is in your folder.
6. **Gallery.** With the Gallery switch off (Settings), no image is added to the Gallery. Switch it on, scan again: the result says "Copy saved to Gallery" and the image is in the Gallery too.
7. **Lost folder.** Revoke access to the folder, then tap SCAN & SEND: a message and a `Settings` button appear, and no camera. Choose the folder again in Settings and go back: the camera starts.
8. **Upright image.** Photograph a document held upright and again held sideways. Open both files: they are upright. The JPEG stores its rotation as an EXIF tag (the emulator reports `orientation=6`), so a viewer that ignores EXIF shows it sideways. Tell me if you see that anywhere you share the file.
9. **Real phone (arm64).**
   - Build: `flutter build apk --debug --target-platform android-arm64`
   - APK: `build\app\outputs\flutter-apk\app-debug.apk`
   - Install on your phone (`adb -s <your-phone> install -r` that file), then check focus, light and document sharpness with the real camera.
10. **Dark mode.** Switch the device to dark mode: the camera screen, the messages, the dialog and the result screen are readable.

## For Claude Code (automated runs, no human help)

Only on the Claude Code emulator (`Claude_Code_Test`), never on the user's.

`flutter test` installs the app fresh on every run and removes it afterwards,
so the CAMERA permission is lost each time and the system dialog would wait
for a tap. Run the integration tests through the helper, which checks the AVD
name and grants the permission with adb right after the install:

```
adb devices
tool/run_integration_test.sh <claude-code-device> integration_test/camera_smoke_test.dart
```

After a manual `adb install` or uninstall, grant it again:
`adb -s <device> shell pm grant com.example.one_click_scan android.permission.CAMERA`.
If the dialog shows up anyway, `camera_smoke_test` fails after 20 seconds
with a message that says what to do; it does not hang.
