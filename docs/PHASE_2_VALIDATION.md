# Phase 2: manual validation (performed by the user)

OCR inside the app: after a scan you can open "OCR text (check)" and see the
text of every page with its confidence and geometry. This screen is a check
tool, not the final UX. Everything is read on the phone: nothing is sent
anywhere.

Real documents stay on your phone. Do not send photos or text of them. What I
need back are **numbers** (steps 4 to 9 say which) and your verdict.

## 1. Install

- APK (arm64, release, R8 on): see the path and size in the report that came
  with this phase (`build\app\outputs\flutter-apk\app-release.apk`).
- It replaces the earlier Scan build; your settings and your folder stay. The
  first start after the update gives the OCR language a default (step 2).
- The APK is bigger than before: it carries the two language packs (about
  15.7 MB), the detector (4.8 MB) and the ONNX Runtime library.

Build it yourself:

```
tool/fetch_ocr_models.sh           # once; downloads and verifies the models
flutter build apk --release --target-platform android-arm64
```

## 2. The language setting

1. Settings, scroll to **Text reading language (OCR)**.
2. Expected default: **Greek + English** on a phone set to Greek, **Latin
   script** on any other language.
3. Pick the other one and leave Settings; come back: the choice stays.
4. Below it, **Open-source licences** opens Flutter's licence page; the
   PaddleOCR models and ONNX Runtime must be in the list.

Two invented pages to try the packs are in `docs/samples/` (show them on
another screen and scan the screen, or print them):
`phase2_greek_receipt.png` (Greek + English) and `phase2_latin_accents.png`
(German, French, Spanish, Italian, Portuguese lines).

## 3. A first scan

1. Scan one of the samples in **Single page** mode.
2. On "Scan saved" tap **OCR text (check)**.
3. While the page is read you see text only ("Loading the language models",
   "Looking for text", "Reading line 12 of 51") and a bar that moves when a line
   is done. There must be **no spinning circle** on this screen.
4. When it is done you see the summary and the lines. Check:
   - the text is right for the pack you chose (Greek page with the Greek pack,
     the accents page with the Latin pack);
   - **Language pack**, **Time**, **Working image**, **Capture** and **Boxes**
     in the summary;
   - **Show boxes on the image** draws the boxes over the page: they must sit
     on the text, also when you scanned with the phone turned sideways.
5. Copy text puts the visible lines on the clipboard (paste it into a note to
   see it; do not send it to me if it is a real document).

## 4. Wrong pack, on purpose

Scan `phase2_latin_accents.png` with the **Greek** pack, then the Greek receipt
with the **Latin** pack. The text should be clearly worse (the app does not
guess the language; this is why the choice is yours). Send me only:
"wrong pack: readable / garbage" for each.

## 5. A real receipt and a real page

Scan a real receipt, then a dense printed page (Single page). For each, copy
these five numbers from the check screen (no text):

| | receipt | dense page |
|---|---|---|
| Time (s) | | |
| Capture (W x H px, MP) | | |
| Working image | | |
| Boxes (filtered) | | |
| first scan after opening the app, or a later one | | |

The **first scan after opening the app** also pays for loading the models when
the camera was opened only a moment before (the screen then says "Loading the
language models"); later scans do not. Compare **Time** with the spike (phase
1.6: `final_b1` about 1.7 s on the full-size photos, the dense leaflet
about 4 to 5 s): the engine is the same, the pipeline differs only in the
upright working copy.

## 6. Capture resolution (important)

The **Capture** line is the size of the picture the app's camera takes. The
camera is opened with `ResolutionPreset.max`, which in the CameraX backend means
"highest available resolution, and prefer the higher resolution over the
capture rate". Measured on your phone in the first check: **3060 x 4080
(12.5 MP)**, which is what most phones give; larger sizes come from software
modes. The preset is therefore left as it is.

- Up to 8 MP: decoded by Dart in a background isolate.
- 8 MP and above (your 12.5 MP shots too): decoded natively, scaled while
  decoding, never at full size. Works up to 400 MP in the header (a 200 MP
  photo is read this way; the sampled bitmap is at most about 105 MB).
- Above 400 MP, or a file the decoder cannot read: the scan is saved, the
  reading fails with "The picture is too large to read (over 400 megapixels)" or
  "The picture could not be read", and nothing crashes.
- Manual check if you have a very large photo (for example your 200 MP leaflet
  of Phase 1.6c): put it through the app (share or the camera's high resolution
  mode) and tell me the **Capture** line and the **Time**; I could not run a
  200 MP photo on the 2 GB emulator without risking its memory (a 54 MP photo
  was tested instead).

## 7. Multi Page: reading while you shoot

1. Switch to **Multi page**, shoot three pages one after the other, then Done.
2. Open **OCR text (check)**: "Page 1 of 3", arrows to move between pages.
3. Check that the first page is already read when you open the screen (the
   next pages were read while you were photographing).
4. Delete the last shot before Done in another run: the removed page must not
   appear in the check screen.

## 8. Airplane mode

Turn on airplane mode, scan a page, open the check screen. It must work exactly
the same (the app has no network permission at all).

## 9. Handwriting and the confidence filter

Scan a handwritten note (or any page the engine reads badly). Lines below 0.65
are drawn crossed out in the error colour with the label "filtered, low
confidence"; they are not part of the copied text. Send me the confidence
numbers only: for a handful of lines, "readable / rubbish, 0.xx". On invented
pages the emulator gave 0.96 to 1.00 for clean, blurred and faint printed text and
0.38 to 0.60 for pen strokes that are not text; 0.65 is your decision after the
first phone check (it was 0.5). The summary now has a line **Borderline lines
(0.50 to 0.65)**: the number of lines the change from 0.5 to 0.65 moved. On
your real documents, compare that number with what you see: are the lines that
are now crossed out good ones? Send me, per document, the number of boxes, the
filtered count and the borderline count (and "good lines lost: yes/no").

## 10. Release behaviour

The APK is a release build with R8 (code shrinking). The emulator smoke test
ran this same build; on the phone, check that the first scan works and the
camera, the scan, the Gallery switch and the settings behave as in Phase 1.2.
If anything crashes only in this build, send the time and what you tapped.

## What to send me

- Step 2: default pack shown (yes/no as expected).
- Step 3: "boxes sit on the text: yes/no", "any spinner: no".
- Step 4: wrong pack results (one word each).
- Step 5: the table.
- Step 6: **Capture** size of your phone's camera.
- Step 7: "first page already read: yes/no".
- Step 8: works in airplane mode: yes/no.
- Step 9: a few confidence numbers.
- Step 10: anything that crashed.

---

## Results on the emulator (`Claude_Code_Test`, x86_64, 2 GB RAM)

These are **not** phone speeds. The emulator is x86 under software rendering;
the numbers show that the pipeline works and how it is shaped, nothing more.
Times are not asserted by any test.

### Tests

- Unit and widget tests: 429 (225 before Phase 2), all green. They cover the
  pixel maths and DB post-processing on synthetic arrays, CTC with blanks,
  repeats and the dictionary, the image header and EXIF orientation 0 to 9
  (including false `ExifImageWidth/Height`), the 8 MP, 50 MP and 400 MP limits, the Dart
  maker for EXIF 1 to 8, model verification (right, wrong, missing), the pack
  registry and the stored choice, the use cases with a fake engine (success,
  timeout, cancel, failure, filter, pipelining of several pages), the cubits,
  the check screen and the pack picker, and that no OCR source file uses the
  network.
- Integration tests on the emulator with the real models
  (`integration_test/ocr_engine_test.dart`, 14 tests; `ocr_flow_test.dart`, the
  whole app with a camera that hands out invented pages; the earlier
  integration tests still pass).
- Release smoke (`tool/run_ocr_release_smoke.sh`): a release APK with R8 reads
  a page, makes the working copy of a 12 MP photo natively, opens the real camera
  and uses `shared_preferences`. It found that R8 broke `shared_preferences`
  (NoSuchMethodError, then ClassNotFoundException for Kotlin classes reached
  through JNI); `android/app/proguard-rules.pro` now keeps them and the smoke
  passes (OCR, preferences, camera). Only these plugins were exercised in a
  release build: the Gallery copy (`gal`) and the SAF folder code were not.
- The emulator camera (virtualscene, `ResolutionPreset.max`) shoots 1280 x 960
  with EXIF orientation 6; it says nothing about the phone.

### Reading (invented pages, Roboto, 1240 px wide)

| Check | Result |
|---|---|
| Greek + English receipt, Greek pack: key tokens | 100% (14 of 14), 11 boxes |
| Accents page (de, fr, es, it, pt), Latin pack: key tokens | 100% (20 of 20), 6 boxes |
| Coordinates | all quads inside 0..1, reading order top to bottom |
| EXIF 0 (invalid), 3, 6, 8 | same size and key tokens as the upright page |
| Native and Dart maker, EXIF 0 to 9 | same size, same four quadrant colours |
| 12 MP photo (4000 x 3000), also with EXIF 6 | native decode, working copy 2560 x 1920, key tokens 100% |
| Real 54 MP photo (8200 x 6600, above the 50 MP full-decode limit) | native sampled decode, working copy 2560 long side, key tokens 100%, 2.3 s in total, peak RSS 714 MB |
| Header above 400 MP (25000 x 20000) | refused as too large, nothing decoded, no crash |
| 200 MP header with no image data | native decode tried, fails as unreadable, no crash, the next page reads |
| Cancel after 300 ms, then the next call | `cancelled`, the next call succeeds |
| Timeout with a 5 ms limit, then the next call | `timedOut`, the next call succeeds |
| Damaged model file (one byte changed) | refused by the SHA-256, file removed, extracted again on the next call |
| Multi Page, 2 pages | in capture order |

### Times and memory (emulator, not phone speed)

| | |
|---|---|
| first page after a cold start (models extracted, hashed, loaded; Dart prepare) | about 5 s in total, 2.2 s of it in the engine |
| a page with the models loaded | 0.7 to 2.0 s in the engine |
| two pages in a row | 2.8 s |
| longest gap of a 20 ms timer on the UI isolate while a page is read | 47 to 112 ms |
| peak RSS of the test process (debug build, includes the test's own page rendering) | 494 MB after single pages, 648 to 683 MB after the 12 MP photo |
| peak RSS of the release smoke | 330 MB |

### Confidence of lines (for the threshold)

| Page | lines | min | median | max | below 0.5 |
|---|---|---|---|---|---|
| clean | 11 | 0.96 | 0.98 | 1.00 | 0 |
| blurred (Gaussian radius 3) | 11 | 0.97 | 0.99 | 1.00 | 0 |
| faint (35% contrast) | 11 | 0.97 | 1.00 | 1.00 | 0 |
| pen strokes that are not text | 8 | 0.38 | 0.48 | 0.60 | 5 (all 8 below 0.65) |

The spike has no confidence study (it recorded mean confidences only). The
threshold is 0.65 by the user's decision (`OcrConfig.minLineConfidence`); on
these invented pages it flags all eight non-text lines (the maximum was 0.60)
and none of the readable ones (the minimum was 0.96). Real handwriting and
faded thermal paper are not covered; step 9 asks for the borderline numbers
from the phone.

