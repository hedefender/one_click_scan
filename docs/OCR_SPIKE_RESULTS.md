# OCR spike results (Phase 1.5)

Status: measured on synthetic documents on the Claude Code emulator (x86_64,
release build). **Not yet measured:** real phone times, real documents (the
user does that, see `PHASE_1_5_VALIDATION.md`). The recommendation below is
therefore conditional on those two checks.

Code: `spikes/ocr_spike/` (separate Flutter project, not part of Scan; its
models are downloaded by `tool/fetch_assets.sh` and are not committed).

## 1. Summary and recommendation

| Engine | Verdict |
|---|---|
| **PaddleOCR PP-OCRv5** (mobile detection + one recognition model per language, ONNX Runtime) | **Recommended primary engine** for Greek, English, Spanish and Russian. Best accuracy on every metric except box granularity. Cost: about 450 lines of own Dart (pre/post-processing, CTC), 41 MB per language set. |
| **Tesseract 5** (`ell+eng`, `fast` data) | **Fallback / second candidate.** Mature, reads mixed languages in one pass, word boxes. Clearly good only with page mode 6 and upright pixels; weaker on low contrast, upper-case accents and `µ`. |
| ML Kit Text Recognition v2 (Latin) | **Rejected.** No Greek or Russian (Greek text comes out as transliterated garbage, 0% of Greek letters correct). Fine for plain Spanish/English, but that is covered by the two engines above. |

Reasoning:

- On the 50 upright synthetic images (clean, ±3°, blur, low contrast and
  noise), Paddle makes **1.8% character errors**. Tesseract makes 19.9% (`best`)
  and 21.0% (`fast`) in its automatic page mode, because it then reads blocks,
  not rows (see 3). With page mode 6 (a separate run on 40 of those images:
  clean, +3°, blur, low contrast) it makes 3.2% (`best`) and 5.1% (`fast`),
  against 1.9% for Paddle on the same 40 images.
- Paddle finds **195 of 200 key values** exactly (200 of 200 when Greek/Latin
  look-alike letters are treated as equal); Tesseract 185 to 187.
- Paddle produces the Greek `μ` (U+03BC) and never the micro sign (332 `μ`, 0 `µ`). Tesseract
  produces `µ` (U+00B5) in 19% to 32% of cases.
- Paddle keeps the row structure ("ΣΥΝΟΛΙΚΟ ΠΟΣΟ ΠΛΗΡΩΜΗΣ  84,36 €" stays on one
  line), which is what the later parsing in Budget needs.
- Paddle's weak point is Greek/Latin look-alike letters (it writes `Ε` or `E`
  at random inside a Greek word: "ΔΕIΓMΑ", "Inνoice"). It costs 5 of 200 exact
  key matches (the shop name) and is visible in mixed Greek/English text (bag
  of words 85% against 76% for Tesseract, which is still better than Tesseract).
- **Decision still open:** the synthetic fonts are clean. Thermal paper, folds
  and shadows are not simulated. The user's real-document check decides if
  Paddle's lead holds. Phase 2 should hide the engine behind `OcrEngine` (see 7)
  so that the Tesseract fallback stays cheap.

A combination per language is possible but not needed: Paddle has a model for
each language (`greek` covers el+en, `latin` covers en+es, `eslav` covers ru).
A document that mixes Greek and Russian is not handled by one model.

## 2. Engine by metric (50 upright images per engine: clean, ±3°, blur, low contrast+noise; 10 documents)

CER is the character error rate in reading order. sCER sorts the words of both
texts first, so layout and reading order do not count (a fairer number for
tables). Key tokens: shop name, tax number, date and total, four per document.
All times from the emulator (x86_64), not representative for a phone.

| Metric | ML Kit | Tesseract fast | Tesseract best | PaddleOCR |
|---|---|---|---|---|
| CER, plugin default mode (psm 3) | 79.4% | 21.0% | 19.9% | **1.8%** |
| CER, psm 6 (single block; 40 of the images) | n/a | 5.1% | 3.2% | 1.9% (same 40) |
| sCER (order-free) | 62.8% | 14.5% | 11.4% | **6.3%** |
| WER (psm 3 / Paddle) | 89.3% | 31.2% | 28.2% | **7.6%** |
| Bag-of-words recall | 38.9% | 85.0% | 88.3% | **92.4%** |
| Key tokens exact (of 200) | 147 | 187 | 185 | **195** |
| Key tokens, look-alike letters folded | 147 | 187 | 185 | **200** |
| Greek lower-case with accents | 0% | 82% | 81% | **100%** |
| Greek upper-case with accents | 0% | 65% | 75% | **77%** |
| Final sigma `ς` | 0% | 89% | 90% | **100%** |
| Digits (Greek documents) | 40% | 82% | 82% | **100%** |
| `μ` (U+03BC) produced | 0 | 211 | 250 | **332** |
| `µ` (U+00B5) produced | 0 | 98 | 59 | **0** |
| Time per A4 image (emulator) | 1.0 s | 0.48 s | 3.3 s | 1.0 s |
| Boxes | block/line/element | line + word (hOCR) | line + word (hOCR) | line segment (rotated, as bounds) |
| Confidence | line | word | word | per recognised segment |
| Languages in one pass | latin only | any combination (`ell+eng`) | any combination | one model per language set |

Notes on the table:

- Per-category accuracy comes from an optimal alignment of reference and
  hypothesis, over the Greek documents (clean, ±3°, blur, low contrast; the
  rot90 images are left out).
- `µ`/`μ`: the reference text uses `μ` in Greek words and one `µ` in a unit
  ("25 µm"); all engines turn the unit into `μ` or lose it, so "mu_micro"
  correctness is 0% for everyone. What matters is that Paddle never emits the
  micro sign, Tesseract does in a fifth to a third of the cases.
- Upper-case accents are low for everyone (the synthetic line is a stress test:
  "ΆΛΦΑ ΈΝΑΣ ΉΧΟΣ ΊΣΩΣ ..."). Modern typography drops those accents on shop
  receipts.
- Tesseract `fast` against `best`: `best` is about 7 times slower and has 4
  times the data (24 MB against 5.5 MB for `ell+eng`) for 3 points less sCER.
  `fast` is the sensible Tesseract choice.
- Handwriting: not tested (expected to fail for all, as the plan says).

Size added to the APK (arm64; native libraries and models as stored in the spike
APK, `tessdata` as raw file size; the APK compresses the traineddata files, to
about 5 MB for all four `fast` and 45 MB for all four `best`):

| Component | Size |
|---|---|
| ONNX Runtime native library (arm64) | 28.7 MB |
| PP-OCRv5 mobile detection | 4.8 MB |
| Recognition, Greek (+English) | 7.8 MB |
| Recognition, Latin (English/Spanish) | 7.9 MB |
| Recognition, East Slavic (Russian) | 7.9 MB |
| **Paddle total: Greek only / all three** | **41 MB / 57 MB** |
| Tesseract native libraries (arm64) | 7.5 MB |
| `tessdata_fast` `ell+eng` / all four languages | 5.5 MB / 11.7 MB |
| `tessdata_best` `ell+eng` / all four languages | 24 MB / 53 MB |
| **Tesseract total: `fast` `ell+eng` / four languages** | **13 MB / 19 MB** |
| ML Kit (arm64 library; the Latin model is inside it) | 11.1 MB |

The spike APK is 225 MB because it carries everything for all three ABIs. A
production build keeps arm64 (and armeabi-v7a if wanted), which is what the
figures above describe.

## 3. Results by document type and condition

Same 50 upright images per engine. CER / sCER (percent), key tokens exact.

| Type | n | Paddle CER / sCER / keys | Tesseract fast (psm 3) CER / sCER / keys | Tesseract best (psm 3) CER / sCER / keys |
|---|---|---|---|---|
| Receipts (3 documents) | 15 | 1.6 / 4.2 / 60 of 60 | 14.5 / 17.9 / 51 | 11.6 / 11.3 / 55 |
| Bills (2) | 10 | 1.0 / 7.5 / 40 of 40 | 31.9 / 11.3 / 39 | 31.3 / 7.2 / 36 |
| Two columns (1) | 5 | 0.6 / 2.3 / 20 of 20 | 25.1 / 8.8 / 20 | 23.5 / 2.6 / 20 |
| Mixed Greek/English (2) | 10 | 3.4 / 11.7 / 35 of 40 (40 folded) | 17.7 / 23.0 / 37 | 17.8 / 24.0 / 35 |
| Spanish (1) | 5 | 1.6 / 5.2 / 20 of 20 | 24.5 / 2.3 / 20 | 24.7 / 5.5 / 19 |
| Russian (1) | 5 | 2.3 / 4.3 / 20 of 20 | 17.7 / 11.8 / 20 | 18.2 / 9.3 / 20 |

By condition (10 documents each), Paddle CER / sCER and Tesseract `fast`:

| Condition | Paddle CER / sCER | Paddle keys | Tesseract fast CER / sCER | Tesseract fast keys |
|---|---|---|---|---|
| Clean | 1.7 / 5.9 | 39 of 40 | 31.6 / 9.4 | 40 |
| Rotated +3° | 1.7 / 6.3 | 39 | 12.3 / 17.4 | 35 |
| Rotated −3° | 1.6 / 6.0 | 39 | 16.3 / 14.2 | 38 |
| Blur | 1.7 / 5.2 | 39 | 12.6 / 14.3 | 37 |
| Low contrast + noise | 2.4 / 8.0 | 39 | 32.2 / 17.2 | 37 |

Reading the numbers:

- Tesseract with its default page mode (3, automatic) cuts a page into blocks
  and reads block after block, so a "label ... amount" row becomes a label in
  one place and the amount somewhere else. That gives the high CER. With page
  mode 6 the CER drops to 3.2% (best) and 5.1% (fast) on the same images (40
  images: clean, +3°, blur, low contrast). So the mode must be chosen on purpose;
  mode 6 loses the multi-column handling (not measured separately).
- Both engines survive ±3° and blur. Low contrast with noise costs Tesseract
  more (sCER 17% against 8%).
- For the two bills, Tesseract `best` finds 36 of 40 key values; Paddle finds
  all 40.
- Detection input size: 1280 instead of 960 pixels changed nothing (CER 1.8%
  against 1.9%, 17% slower). 960 stays the default.

## 4. Orientation / EXIF (open question since Phase 1.1)

Camera JPEGs keep the pixels as the sensor wrote them and add an EXIF tag. The
same document was fed (a) with the EXIF tag 6 on sideways pixels (`rot90_exif`)
and (b) as sideways pixels without a tag (`rot90_raw`), and (c) as upright
pixels (clean). Key tokens exact, of 40:

| Engine | Upright | Sideways with EXIF tag | Sideways, no tag |
|---|---|---|---|
| ML Kit | 28 | 28 (honours the tag) | 28 (fails, same numbers) |
| Tesseract | 37 to 40 | **0** | **0** |
| PaddleOCR (own pipeline) | 39 | 39 | **17** |

Findings:

- **Tesseract ignores EXIF** (same failure with and without the tag). It needs
  upright pixels.
- ML Kit's file loader applies the tag.
- Paddle read the EXIF case correctly **only because `package:image` already
  applies the orientation when decoding** (checked: a 20×40 stored image with
  tag 6 decodes as 40×20). With a decoder that ignores the tag it would behave
  like the "no tag" column. Paddle also does not detect a sideways page by
  itself (it has no document orientation model in this setup).
- Nobody recovers a 90° page without the tag. The Tesseract orientation
  detection (`osd.traineddata`, page mode 0/1) and PP-LCNet document
  orientation model exist but were not tried.

**Consequence for Phase 2/3:** bake the rotation into the pixels once, at the
beginning of processing (when the file is read for OCR and PDF), and give every
engine upright pixels. Then the choice of engine does not matter for this
question. Baking at capture time, in `./pictures/`, is not required by any
engine. (The decision itself stays with the user.)

## 5. Geometry and searchable PDF

- Tesseract (hOCR): line boxes and word boxes with confidence per word. The
  best fit for an invisible text layer (one text object per word).
- Paddle: one box per detected text segment (usually a line, sometimes a part
  of a line when the gap is large), as a rotated rectangle (the spike keeps its
  bounding box). It is enough for a text layer with one text object per segment
  stretched to the box width. Word boxes would need the CTC time steps (each
  step maps to a horizontal position); not built.
- ML Kit: block, line, element boxes.
- Boxes are in the pixel space of the image that was given to the engine, so
  the baked, upright image must be the one used for the PDF page.

## 6. Cost and risks of integration

| Topic | PaddleOCR (ONNX Runtime) | Tesseract | ML Kit |
|---|---|---|---|
| Package / wrapper | `flutter_onnxruntime` 1.9.0 (MIT, published 2026-10-06, 51 likes, Android + iOS + desktop). It only moves tensors; Maven `onnxruntime-android` 1.28.0 (MIT) | `flutter_tesseract_ocr` 0.4.31 (BSD-3, 2026-06-01, 216 likes): **does not build** with the current AGP 9.1 / Gradle 9 template (`jcenter()` removed, `kotlin-android` plugin refused). The main Scan app uses the same AGP 9.1. The spike therefore uses its own 75-line Kotlin channel on `tesseract4android` 4.9.0 (Apache-2.0, JitPack, last release 2025-06) | `google_mlkit_text_recognition` 0.17.1 (MIT; the SDK itself falls under Google's terms) |
| Own code | ~450 lines Dart: resize/normalise, DB post-processing (connected components + PCA box, unclip), rotated crops, CTC decode, row grouping; written and tuned in this session | ~140 lines Dart + 75 lines Kotlin (+ hOCR parser) | ~50 lines |
| Speed risk | All pixel loops and the tensor transfer are in Dart/method channel: the per-line `OrtValue` calls cost about 30 ms each on the emulator, with 23 segments per A4. The real phone is unknown. A native (Kotlin/Rust) pre/post-processing is the escape route | Native, fast (`fast`: 0.5 s) | Native |
| Models | Apache-2.0 (PaddleOCR); ONNX conversion by a third-party mirror (Hugging Face, Apache-2.0), mobile detection from another mirror. Both are not official PaddlePaddle ONNX files. Supply-chain: pin and checksum; or convert from the official models ourselves | Apache-2.0 (tessdata) | in the library |
| Minification | `-keep class ai.onnxruntime.** { *; }` needed | none | **With R8 minification on, the Latin recognizer crashed** (`NullPointerException` in obfuscated code) even with the `-dontwarn` rules for the Korean/Chinese/Japanese/Devanagari options; it works with minification off. Not diagnosed further (rejected engine) |
| Maintenance | `onnxruntime` is MIT, pushed daily. Models are frozen files. Own code is ours | Library alive but slow (last release 2025-06); tessdata repositories last pushed in 2024 | Google |
| iOS | `flutter_onnxruntime` supports iOS (needs iOS 16, static linkage); the Dart pipeline is portable | Possible (SwiftyTesseract or the C++ library), but separate code, not tried | Supported, but no Greek |
| Offline / privacy | Fully local; models bundled | Fully local; data bundled | Bundled model for Latin; SDK is closed source |
| Network permission | none in the plugin (the spike removes `INTERNET`/`ACCESS_NETWORK_STATE` that other libraries merged in) | none | the final spike manifest was merged with `INTERNET` and `ACCESS_NETWORK_STATE` from some library (not traced to a single one); both are removed with `tools:node="remove"` |

Other risks:

- Both candidate engines need the page upright and roughly horizontal (± a few
  degrees). Crop, perspective and contrast (Phase 6) will help.
- No wrapper was found for PP-OCRv5 with Greek: `paddle_ocr_native` 0.1.1
  (Apache-2.0, Android and iOS, ONNX Runtime) ships PP-OCRv6 weights (29 MB)
  and does not accept custom models in 0.1, so no Greek. `pp_ocr` is for
  Windows/Linux. `flutter_paddle_ocr` uses Paddle Lite, `pdf_ocr_ondevice`
  downloads its models. None was usable; custom code was the only way.
- The ONNX Runtime library is the biggest single item (28.7 MB per ABI).

## 7. Proposed `OcrEngine` interface (Phase 2)

```dart
/// An image that is already upright (EXIF baked in by the caller).
class OcrInput {
  final String path;          // upright JPEG/PNG file, readable by the engine
  final int width, height;    // pixels of that file (box coordinate space)
}

class OcrLine {
  final String text;
  final Rect box;             // axis-aligned, pixels of OcrInput
  final double? confidence;   // 0..1
  final List<OcrWord> words;  // may be empty when the engine has no word boxes
}

class OcrResult {
  final String text;          // lines joined by '\n', rows kept together
  final List<OcrLine> lines;
  final Duration elapsed;
}

abstract interface class OcrEngine {
  /// Languages the installed models can read, as BCP 47 (`el`, `en`, `es`, `ru`).
  Set<String> get supportedLanguages;
  Future<OcrResult> recognize(OcrInput input, {required Set<String> languages});
  Future<void> dispose();
}

sealed class OcrFailure implements Exception {} // ModelMissing, UnsupportedLanguage,
                                                // Unreadable (decode), Cancelled
```

What the spike showed is needed:

- **Input a file path, upright.** ML Kit and Tesseract take a path; Paddle
  decodes it itself. A path also lets the engine run off the UI isolate. The
  caller (not the engine) bakes the EXIF rotation, because Tesseract and a
  tag-ignoring decoder fail otherwise.
- **Languages are an argument, not a constructor detail:** Paddle picks one
  recognition model by language set, Tesseract builds a `ell+eng` string.
- **Output with rows kept together** (one `OcrLine` per visual row), plus word
  boxes when they exist (needed for the text layer in Phase 3).
- **Errors are values** (`OcrFailure`) rather than empty text: ML Kit's crash
  showed that empty text and "engine failed" must differ. Empty text with no
  failure is a valid result (Phase 5 sends the mail anyway).
- Engine instances hold native sessions: `dispose()` and one instance per
  process, created lazily (a Paddle session loads about 12 MB of models; Tesseract
  re-creates its native object when the data variant or language set changes).

## 8. Open questions

1. **Real phone times.** The user's phone decides if the Dart pre/post-processing
   of Paddle is fast enough (emulator: 1.0 s per A4 image; the plan needs a
   target, for example under 5 s per page on the phone).
2. **Real documents.** Thermal receipts, shadows, folds, photographed bills
   (steps 3 to 7 of `PHASE_1_5_VALIDATION.md`).
3. **Is the Greek/Latin look-alike confusion a problem for Budget?** It breaks
   exact matching of shop names. Budget normalises text already; Scan could
   offer the folded text, or Budget could fold. Not a Scan decision yet.
4. **Tesseract page mode.** Mode 6 is accurate but assumes one block; is
   multi-column text a use case? (The two-column test document is read well by
   mode 3, not measured with mode 6.)
5. **Model provenance for Paddle.** Convert and checksum the official models
   ourselves, or accept the Hugging Face mirrors?
6. **Orientation detection.** Do we need to detect 90°/180° pages (no EXIF, a
   scan imported from a file), with Tesseract OSD or PP-LCNet?
7. **A native pre/post-processing** (Kotlin or Rust, the Phase 6 candidate)
   remains an option if Dart is too slow on the phone.
8. **Fine print on the synthetic benchmark:** one font family per document,
   clean rendering, ten documents, one noise seed, a single emulator run.
   Differences of one or two points in the tables are not significant;
   differences of ten points or more (and the failures: ML Kit on Greek,
   Tesseract on sideways pixels) are.
