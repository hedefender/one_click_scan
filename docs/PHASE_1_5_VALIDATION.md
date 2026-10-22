# Phase 1.5: manual validation (performed by the user)

OCR spike. The spike is a separate app in `spikes/ocr_spike/`; the main Scan
app is not touched. Real documents stay on your phone: do not send photos or
text of them, only the "Copy summary" numbers.

1. **Install the spike APK (arm64)** on your phone. It has its own package
   name (`com.example.ocr_spike`), so it does not replace Scan.
   - Build: `cd spikes\ocr_spike`, then `flutter build apk --release --target-platform android-arm64`
   - APK: `spikes\ocr_spike\build\app\outputs\flutter-apk\app-release.apk` (about 225 MB: all models and traineddata for the comparison are inside, nothing is downloaded).
2. **Synthetic benchmark.** Tap "Run synthetic" and wait (several minutes; the
   screen shows progress). Note the total time ("done in ... s") and the
   lines per engine (CER, WER, keys found, ms per image). The times on the
   phone are the ones that count; the emulator times are not representative.
3. **Photograph three of your own documents with the main Scan app**: an
   electricity bill, a supermarket receipt and a coffee-shop receipt (and one
   with bad light if you like). Keep them on the phone only.
4. **Real documents in the spike.** Tap "Pick image" (system file picker; the
   Scan folder `./pictures/` is hidden from the Gallery, so use the picker's
   folders). Choose the language set (`el+en` for Greek). Type 2 to 4 values
   you know are on the document (amount, date, a name). They stay in memory
   only. Tap "Run".
5. **Read the result per engine**: ✓ or ✗ for each value, time in ms, number
   of characters, confidence and whether it returns boxes. Tap an engine to
   see its text on the screen (never saved anywhere).
6. **Send me only the summary**: tap "Copy summary" for each document and
   paste it. No photos, no text of the documents.
7. **Look at the text on the screen** (accents, numbers, Greek vs Latin
   look-alike letters) and tell me in your own words what you see, without
   personal details.

## For Claude Code

- The spike is built and run only on `Claude_Code_Test`:
  `flutter build apk --release --target-platform android-x64 --dart-define=AUTORUN=full --dart-define=DUMP=true`
  starts the synthetic benchmark at launch and prints `OCRBENCH {json}` lines
  (synthetic data only) to logcat. `AUTORUN` can be `full`, `quick`, `one`,
  `exif`. `DUMP=true` also prints the recognised synthetic text.
- Never log or store anything in the real-document mode.
