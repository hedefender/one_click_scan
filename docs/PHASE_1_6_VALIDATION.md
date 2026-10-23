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
     (about 247 MB).
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

## Phase 1.6b: controlled phone measurements (performed by the user)

Why: in your first numbers the recognition time fell into two groups (about
740 ms and 1100 to 1800 ms) and the UI frame counter showed the screen drawing
almost nothing during the fast group. These steps separate the UI load, heat
and screen state from the settings. Same spike app, new APK (arm64); the main
Scan app is not touched. Send only numbers.

Preparation (important):
- Phone **cold and at rest** (not used for a few minutes), **off the charger**,
  battery above 50%, other apps closed.
- **Settings, Display, Screen timeout: 10 minutes or more** (a run takes
  several minutes and you must not touch the screen). If the screen turns off
  during a run, the frame count in the lines drops to about 0 and the run is
  not valid; repeat it.
- Open the app, tap **Perf**. Do not use the other buttons while a step runs.
- Optional but useful: tap **Pick your receipt** (the real receipt you used
  before) and **Pick your hard sample** (the leaflet). Step A uses your
  receipt if picked, otherwise a generated 12 MP receipt.

Steps, in this order, with 3 to 5 minutes of rest between the steps (put the
phone down, screen on, nothing running):

1. **A: UI load A/B** (about 4 minutes: 6 blocks of 5 runs with 30 s pauses).
   Do not touch the screen. When it finishes tap **Copy summary** and send the
   text. Then tap **Clear**.
2. **B: provider x threads** (about 6 to 10 minutes). Before tapping, set the
   UI load switch to the state that A showed to be best (if A is not clear,
   leave `1 fr/s`). Send the summary, then **Clear**.
3. **C: provider accuracy** (about 5 to 8 minutes). Send the summary, then
   **Clear**.
4. **D: best** (about 3 to 6 minutes, longer with the picked samples). It runs
   the setting chosen from B and C (the line "best = ..." under the buttons
   shows which). Send the summary.
5. Tell me in one line: was the screen on all the time, was the phone warm to
   the touch at the end, and the battery temperature before and after if you
   know it.

Notes:
- If you restart the app between steps, B/C/D forget each other's results (the
  "best" falls back to th4 on CPU).
- The lines show the battery temperature as `n/a` if Android does not let the
  app read it. That is expected on many phones.
- Nothing from your images is shown or copied: only counts and distances.

## Phase 1.6c: safe harness and repeat of A to D (performed by the user)

What changed since 1.6b: the spike no longer freezes or dies on a huge photo
(your 200 MP leaflet), every cell is saved before and after it runs, the
screen is kept on while a step runs, the battery temperature and the reason
why a previous run died are read from Android. Install the new APK (arm64);
it replaces the previous spike APK. Send only numbers.

Preparation:
- Phone **cold and at rest** (a few minutes without use), **off the charger**,
  battery above 50%, other apps closed. The screen is now kept on by the app
  while a step runs; you still must not touch it during a step.
- Open **Perf**. Pick **your receipt** and **your hard sample** once
  (Pick buttons). The app skips, with a clear message, any full-size decode of
  an image above 50 MP, and runs its other settings only through the safe path
  (native decode capped at 2560 px), so the 200 MP leaflet is allowed in D and
  in the "Run on them" step.
- "Rest between groups": leave it at 20 s.

If the app is cut or closed by the system anyway:
- Open it again and Perf: a red box says in which cell the run was cut, which
  reason Android recorded for the previous process (for example ANR or
  LOW_MEMORY), and keeps every result saved before it. Tap **Resume** to carry
  on from the next cell (the pick buttons must be used again first if the plan
  used your images; "Copy summary" always includes everything saved).
- Please send me that red box text (it has no personal data), even if you
  resume.

Order (3 to 5 minutes of rest between the steps, screen on, nothing running):

1. **A: UI load A/B** (about 4 minutes). Send the summary, then **Clear**.
2. **F: paired A/B** (about 8 minutes, six comparisons): compares settings alternately
   (A B, B A, ...) to check whether the order of the runs, the batch size, the
   ArgMax model or the background isolate explain the differences. Send the summary, then **Clear**.
3. **B: provider x threads** (two passes, about 12 to 20 minutes). Before
   tapping, set the UI load switch to `1 fr/s`. Send the summary, then
   **Clear**.
4. **C: provider accuracy**. Send the summary, then **Clear**.
5. **D: best**, with both samples picked (runs the 200 MP leaflet through the
   safe path). Send the summary.
6. **G: language packs** (about 3 to 5 minutes, invented documents only).
   Send the summary.
7. One line from you: was the phone warm to the touch at the end?

The summary now also shows `mem rss ... peak ... MB` per cell, the battery
temperature per plan and per group (`n/a` if Android does not give it), and
the reason of the previous process exit.

## For Claude Code

- The spike runs only on `Claude_Code_Test` (never on the user's emulator).
  Build once with `--dart-define=AUTORUN=file --dart-define=DEVICE=emulator`,
  install, then push `autorun.txt` to
  `/sdcard/Android/data/com.example.ocr_spike/files/` with `mode=perf` or
  `mode=acc` and `perf=<groups or experiment ids>`; the app prints
  `PERFBENCH <id> <i>/<n> <json chunk>` lines (timing, synthetic data only) or
  `OCRBENCH {json}` lines (accuracy guard) to logcat.
- Phase 1.6b on the emulator: `mode=study|grid|prov|best|all` (+ `pause=3`) in
  `autorun.txt` (also `paired`, `langs`, and `sample` with `sample=<file>` and
  `perf=<ids>`); output lines are `PERFSTUDY ...` and `PERFSTUDY_DONE`.
- The emulator has 2 GB of RAM: never run the unguarded harness
  (`--dart-define=UNSAFE=true`, reproduction only) on a 200 MP image there; it
  makes the whole emulator unresponsive.
- Emulator (x86) timings are only good for the shares per stage and for
  correctness. Never use them as phone speed.
- Never log or store anything from a real image.
