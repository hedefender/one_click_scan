# Phase 1.1: manual validation (performed by the user)

Fixes after the Phase 1 check: the Gallery switch, the camera screen in
landscape, and the dependency direction. Use your own emulator or phone.

1. **Old test images.** Delete by hand the old test pictures that Photos
   already indexed. The `.nomedia` marker keeps new files out of the Gallery
   but does not remove entries that already exist; they may linger until the
   next media rescan or until you delete them.
2. **Gallery off.** Settings: switch off. Scan. The pictures are in
   `./pictures/` (Files app) and do **not** appear in Photos/Gallery.
   `./pictures/` also contains a small `.nomedia` file (hidden by most file
   managers); leave it there.
3. **Gallery on.** Switch on, scan. **One** copy appears in the Gallery (under
   `Pictures`; since Phase 1.2 it is named `scan_<date>_NN.jpg`, see
   `PHASE_1_2_VALIDATION.md`). `./pictures/` has its own
   file, but it is not shown twice in the Gallery.
4. **Switch text.** The note under the Gallery switch is accurate, in the
   wizard (step 4) and in Settings, in Greek and in English.
5. **Landscape.** Open SCAN & SEND and rotate the phone. The preview fills the
   screen; Single/Multi is at the top; the shutter, Done and delete-last are
   on the right, thumbnails next to them. Nothing is cut or overlapped.
   Repeat in portrait: controls at the bottom.
6. **Rotate in Multi.** Take two pages, rotate the phone, take a third: the
   pages are still there (`Pages: 3`).
7. **Real phone (arm64).** Same steps 2 to 6.
   - Build: `flutter build apk --debug --target-platform android-arm64`
   - APK: `build\app\outputs\flutter-apk\app-debug.apk`

Still open (not changed here): the JPEG keeps its rotation as an EXIF tag.

## For Claude Code

Run integration tests with `tool/run_integration_test.sh <device> <test>`
(see `PHASE_1_VALIDATION.md`, "For Claude Code"). It grants the camera
permission with adb so no dialog needs a tap.
