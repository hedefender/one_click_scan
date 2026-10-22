# Phase 1.6: manual validation (performed by the user)

OCR timing on the real phone. Same separate spike app as Phase 1.5
(`spikes/ocr_spike/`, package `com.example.ocr_spike`); the main Scan app is not
touched. Real documents stay on your phone: do not send photos or text of
them, only the "Copy summary" numbers.

1. **Install the new spike APK (arm64)** on your phone (it replaces the Phase
   1.5 spike, not Scan).
   - Build: `cd spikes\ocr_spike`, then
     `flutter build apk --release --target-platform android-arm64 --dart-define=DEVICE=phone`
   - APK: `spikes\ocr_spike\build\app\outputs\flutter-apk\app-release.apk`
     (about 225 MB).
2. Open the app and tap **Perf** (top right). The page shows a spinner that
   never stops: a stutter in it while OCR runs is the UI jank we want to rule
   out. Keep the phone awake, on the charger or with enough battery, and close
   other apps. Do not touch the screen while a run is going (touching is only
   for the scroll check in step 6).
3. **Cold and warm numbers.** Select the groups `baseline` and `final` and
   leave "Also 12 MP photo-size images" ticked. Tap "Run synthetic scenarios".
   For every cell the app loads the models from scratch, does one run (cold),
   then 3 more runs (warm, averaged). The group `final` also runs `final_b1` (the same without batching), so the two can be compared. The three scenarios are generated on the
   phone with invented content: a typical receipt (~30 lines), a dense A4 page
   (3 columns, ~2000 characters) and a poor-quality capture (blur, low
   contrast, tilt). Tap "Copy summary" and send the text.
   - For the strictest cold number, force-stop the app (long-press the icon,
     App info, Force stop), open it again, and run only `baseline` once more:
     the first cell of that run also pays the operating-system caches.
4. **One setting at a time.** Run the groups `ort`, `det`, `batch`, `pre`,
   `decode` and `isolate` (one or two at a time; each group takes a few minutes
   on the phone) and send the summary of each. These show which setting
   helps on your CPU (threads, XNNPACK, NNAPI, detection size, batching,
   native decoding, background isolate).
5. **Your own hard sample** (the leaflet that took about 5 s). Tap "Pick your
   hard sample", choose it, select `baseline` and `final`, tap "Run on it" and
   send the summary. Only numbers are shown and copied for it: no text, no
   accuracy.
6. **Is the UI smooth?** During a `final` run, scroll the list of results or
   watch the spinner. The summary line also reports frames, slow frames, the
   longest UI stall and the longest platform-channel round trip; a short note
   from you ("smooth" or "stutters at the start / at the end") is useful.
7. **Send me only the numbers** (the "Copy summary" text), plus the one-line
   verdict from step 6. No photos, no document text.

## For Claude Code

- The spike runs only on `Claude_Code_Test` (never on the user's emulator).
  Build once with `--dart-define=AUTORUN=file --dart-define=DEVICE=emulator`,
  install, then push `autorun.txt` to
  `/sdcard/Android/data/com.example.ocr_spike/files/` with `mode=perf` or
  `mode=acc` and `perf=<groups or experiment ids>`; the app prints
  `PERFBENCH <id> <i>/<n> <json chunk>` lines (timing, synthetic data only) or
  `OCRBENCH {json}` lines (accuracy guard) to logcat.
- Emulator (x86) timings are only good for the shares per stage and for
  correctness. Never use them as phone speed.
- Never log or store anything from a real image.
