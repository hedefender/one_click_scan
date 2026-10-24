# OCR spike results (Phase 1.5, performance in Phase 1.6)

Status: measured on synthetic documents on the Claude Code emulator (x86_64,
release build). **Not yet measured:** real phone times, real documents (the
user does that, see `PHASE_1_5_VALIDATION.md`). The recommendation below is
therefore conditional on those two checks. Section 9 (Phase 1.6) adds the
timing breakdown of the Paddle pipeline; its phone columns are filled in from
the user's numbers (`PHASE_1_6_VALIDATION.md`).

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

## 9. Performance (Phase 1.6)

Question: on the user's phone (Xiaomi Note 14 Pro 5G, arm64) Paddle took
**4999 ms** for one dense page (51 boxes, about 2000 characters). Where does the
time go, and how far do cheap measures get us? Target on the phone, warm run:
a typical receipt (20 to 40 lines) at most 2 s, a dense page at most 4 s.

**How to read the numbers.** Every figure below was measured on the Claude Code
emulator (x86_64, release build, no animation running, host CPU shared). They
are good for the **share per stage** and for **correctness**; they are **not**
phone speed (the emulator also moves by about ±15% between identical runs).
The cells marked `pending` are filled in from the user's "Copy summary".
Code: `spikes/ocr_spike/lib/engines/paddle*`, `lib/bench/perf_*`.

### 9.1 What was measured

The Paddle engine now times every stage (microseconds, charged to consecutive
laps so nothing is lost), and a "lab" runs each experiment on three invented
scenarios generated at run time from a fixed seed: **receipt** (about 30
lines, 800 px wide), **dense** (3 columns x 17 lines, 51 boxes, about 2000
characters, 1654 px wide) and **poor** (the receipt with tilt, blur, low
contrast and noise). Each also exists as a **camera-size** image (scaled to
about 12 MP, JPEG), which is what the decoder really sees in Scan. A cell is:
sessions closed and loaded again, one **cold** run, then three **warm** runs
(mean). Each cell also records the CER and the key values found, and the UI
health during the cell: the longest stall of the UI isolate (8 ms timer), the
longest round trip of a trivial platform-channel call, and frame times.

Stages: `decode` (file read, JPEG decode, RGBA/RGB), `detPre` (resize and
normalise into the tensor), `detXfer` (tensor to the plugin, result back, copy
to `Float32List`), `detRun` (ONNX Runtime on the detector), `detPost`
(threshold, connected components, boxes, unclip, reading order), `recCrop`
(rotated crop and resize per line), `recXfer` (tensor in, result out, dispose),
`recRun` (ONNX Runtime on the recogniser), `ctc` (greedy decoding, lines).

### 9.2 Baseline (the Phase 1.5 pipeline) and what dominates

Warm ms and share of the total, emulator, native size (as drawn) and camera size:

| Scenario | Total | decode | detPre | detXfer | detRun | detPost | recCrop | recXfer | **recRun** | ctc | phone |
|---|---|---|---|---|---|---|---|---|---|---|---|
| receipt | 1780 | 55 (3%) | 42 (2%) | 79 (4%) | 205 (12%) | 9 (1%) | 69 (4%) | 398 (22%) | **913 (51%)** | 9 | pending |
| dense | 2958 | 53 (2%) | 26 (1%) | 46 (2%) | 85 (3%) | 6 (0%) | 265 (9%) | 582 (20%) | **1875 (63%)** | 20 | pending (4999 ms before) |
| poor | 1580 | 73 (5%) | 40 (3%) | 74 (5%) | 165 (10%) | 6 (0%) | 45 (3%) | 384 (24%) | **784 (50%)** | 8 | pending |
| receipt, 12 MP | 2228 | **551 (25%)** | 42 | 70 | 176 (8%) | 6 | 63 | 394 (18%) | 913 (41%) | 11 | pending |
| dense, 12 MP | 3036 | **502 (17%)** | 28 | 48 | 98 (3%) | 9 | 151 (5%) | 489 (16%) | 1693 (56%) | 17 | pending |
| poor, 12 MP | 2041 | **569 (28%)** | 35 | 78 | 158 (8%) | 12 | 46 | 332 (16%) | 800 (39%) | 9 | pending |

Cold runs (models loaded from scratch plus the first run) are only 4% to 12%
above warm on the emulator (1985 / 3078 / 1724 ms); loading the sessions takes
about 0.2 s once the model files exist in the cache (0.47 s the first time of
a run). The phone's cold run may differ more (page cache).

What dominates:

1. **The recognition network (`recRun`) is 39% to 63%** of the total: one run
   per text line, about 19 ms (receipt) to 37 ms (dense) each. This is ONNX
   Runtime compute; Dart code does not touch it.
2. **The plugin channel (`detXfer` + `recXfer`) is 18% to 29%.** It is mostly
   a per-call cost: every line costs five channel calls (create tensor, run,
   read result, dispose x2); outside `recRun` that is about 11 ms per line on
   the dense page, including the copy of the `[T, 356]` probability matrix.
3. **Decoding a 12 MP JPEG in pure Dart is 17% to 28%** and happens on the UI
   isolate (stall 0.5 to 0.65 s). Scan's photos are of that size.
4. The Dart pixel work (`detPre`, `detPost`, `recCrop`, `ctc`) is 7% to 11% in
   the Phase 1.5 form (the crop of the dense page, 265 ms, is the largest
   single piece) and 3% to 4% once it is written with typed lists.
5. Detection (`detRun`) is small (3% to 14%).

Caution for the phone: the share of Dart code can be larger there (Dart on an
Arm core) or smaller than on the host. The phone numbers decide this; the
instrumentation reports the same stages.

### 9.3 Experiments (one change at a time against the baseline)

Warm ms on the emulator, native-size images; camera size in brackets where it
was run. CER and keys come from the accuracy guard (the synthetic benchmark of
Phase 1.5: 10 documents x 4 conditions, clean, +3 degrees, blur, low contrast;
baseline **CER 1.8%, 156/160 key values**). The guard limit is about 1 point.

| Experiment | receipt | dense | poor | CER / keys | Reading |
|---|---|---|---|---|---|
| base (4 threads, detection 960, one line per run, pure-Dart decode) | 1780 (2228) | 2959 (3036) | 1580 (2041) | 1.8% / 156 | |
| 1 thread | 1738 | 3258 | 1649 | 1.8% / 156 | |
| 2 threads | 1422 | 2508 | 1382 | 1.8% / 156 | emulator has few cores |
| 6 threads | 2488 | 4393 | 2189 | 1.8% / 156 | more threads slower here |
| 8 threads | 3082 | 5907 | 2658 | 1.8% / 156 | |
| XNNPACK + CPU | 2755 | 4000 | 2736 | 1.8% / 156 | works (session created); slower on x86 |
| NNAPI + CPU | 1923 | 2627 | 1573 | 1.8% / 156 | works; the emulator has no accelerator |
| no thread spinning | 1816 | 3074 | 1652 | 1.8% / 156 | no gain |
| detection 640 | 1290 | 2340 | 1195 | 2.0% / 154 | poor image: 3 of 4 keys; not safe |
| detection 800 | 1406 | 2400 | 1353 | 1.8% / 155 | -21% on receipt; one key lost |
| detection 1280 | 1924 | 2965 | 1773 | 1.8% / 156 | no gain, slower |
| recognition batch 4 | 1446 | 2846 | 1315 | 2.0% / 156 | -4% to -19%, CER +0.2 |
| recognition batch 8 | 1700 | 3426 | 1434 | 2.1% / 156 | slower than batch 4 (padding) |
| typed-list pixel loops | 1416 | 2439 | 1326 | 1.8% / 156 | **-16% to -20%**, identical text |
| ArgMax inside the recognition model | 1532 | 2569 | 1474 | 1.8% / 156 | -7% to -14% (noise level), identical text |
| native decode, full size | 1408 (1707) | 2590 (2601) | 1398 (1564) | 1.8% / 156 | 12 MP: decode 550 to 260 ms |
| native decode, max side 2560 | 1584 (1517) | 2595 (2577) | 1371 (1511) | 1.8% / 156 | 12 MP: decode 550 to 100-170 ms |
| native decode, max side 1600 | 1492 (1493) | 2664 (2525) | 1435 (1454) | 1.8% / 156 | one key lost on a poor 12 MP image in the lab |
| background isolate | 1356 | 2471 | 1272 | 1.8% / 156 | UI stall 520 ms to 25 ms |
| isolate + typed-list loops | 1389 | 2462 | 1207 | 1.8% / 156 | |
| **final** (typed loops, ArgMax model, native decode max 2560, batch 4, isolate, 4 threads) | 1318 (1318) | 2671 (2650) | 1127 (1211) | 2.1% / 156 | **-26% / -10% / -29%**; 12 MP: -41% / -13% / -41% |
| final without batching (`final_b1`) | pending | pending | pending | 1.8% / 156 | to compare on the phone |

(The emulator moves by about ±15% between identical runs: the reading column
only calls out differences clearly larger than that, or exact shares.)

Notes on the experiments:

- **Threads, XNNPACK, NNAPI** cannot be decided here: the emulator is a host
  process with few cores, so more threads were slower. On the phone these are
  the experiments that matter most (the Dimensity 7300 has 4 big and 4 little
  cores; 4 or 6 threads are the candidates). What the plugin exposes:
  `intraOpNumThreads`, `interOpNumThreads`, the provider list (CPU, XNNPACK,
  NNAPI are built into its ONNX Runtime 1.28.0) and free-form session config
  entries. XNNPACK is added with an empty options map, so its own thread count
  cannot be set. **The graph optimisation level is not exposed** (ONNX
  Runtime's default, "enable all", applies). The plugin serialises all calls
  (one lock, one task queue), so two sessions cannot run at the same time.
- **Detection size** barely changes the total (the detector is 3% to 14%).
  640 loses key values on the poor image, 800 loses one. Keep 960.
- **Batching** trades fewer channel calls (13 instead of 51 on the dense page:
  `recXfer` 582 to 240 ms) for padded compute (`recRun` about +20% there).
  The net result is within the noise of the emulator and costs 0.2 to 0.3
  points of CER (padding changes the activations). Needs the phone to decide;
  the safe default is batch 1.
- **Typed-list loops** are the largest pure-Dart win: the same arithmetic
  without a list allocated per pixel. The detection tensor goes from 26-42 ms
  to 10-15 ms, the crops of the dense page from 265 ms to 66 ms. Text and
  accuracy are identical to the baseline.
- **ArgMax inside the model:** the recogniser's last node is a Softmax over
  356 classes; adding ArgMax and ReduceMax to the graph returns `[B, T]`
  indices and probabilities instead of `[B, T, 356]`. Same weights, verified to
  give the same indices (`tool/make_rec_variants.py`; a derived file built from
  the downloaded model, not committed). Alone it removes only the CTC scan and
  the copy (the channel round trips remain); together with batching `recXfer`
  falls from 584 to about 160 ms on the dense page.
- **Native decode** (Flutter's own codec, scaled while decoding): a 12 MP
  JPEG goes from 0.5 s in Dart to 0.26 s at full size and 0.1 to 0.17 s with a maximum
  side of 2560, and it runs on a native thread, not on the UI isolate. It
  applies the EXIF orientation like `package:image` (checked: the sideways image
  with the tag reads at CER 1.8%; without the tag 60%, as for every engine). A
  cap of 1600 px lost a key value on a poor 12 MP image; **2560 is the safe
  cap.** The codec is available only in the root isolate, so with the
  background isolate the decode stays in the root isolate and the pixels are
  handed over.
- **int8 quantisation** was tried and dropped: dynamic quantisation of the 13
  `MatMul` nodes does not change the model size (the weights are mostly in
  `Conv`), and quantising `Conv` needs calibration data and was not attempted.

### 9.4 UI smoothness (experiment 6)

Longest stall of the UI isolate during a cell (ms), emulator, with a spinner
animating on screen:

| | receipt | dense | poor | 12 MP |
|---|---|---|---|---|
| baseline (all on the UI isolate) | 519 | 98 | 123 | **534 to 627** |
| native decode only | 68 | 55 | 67 | 52 to 71 |
| background isolate | 31 | 43 | 25 | n/a (decode stays in the root isolate) |
| final | 43 | 25 | 50 | 32 to 54 |

The baseline stalls the UI isolate for half a second (the JPEG decode in Dart,
the pixel loops, the first detection tensor); the final configuration keeps it
under about 50 ms. The plugin runs ONNX Runtime on its own background task
queue, so the platform thread is not blocked either. Frame counts and "slow
frames" in the logs come from the emulator's software renderer and are not
meaningful; the stall figure is. **The phone must confirm this** (step 6 of
`PHASE_1_6_VALIDATION.md`).

### 9.5 Recommendation for Phase 2

- **Implementation language: Dart, no native or Rust code now.** The
  measurements say the Dart pixel work is 3% to 4% of the time once typed
  lists are used, and the part that cannot be moved into Dart (ONNX Runtime
  compute and the plugin channel) is not helped by Rust pre/post-processing.
  ADR-002 and the cargo-ndk / flutter_rust_bridge / multi-ABI cost therefore
  stay out of Phase 2. **If the phone shows otherwise** (Dart stages above
  25% of the warm time on the dense page), the order of attack is: move only
  crop + detection tensor + post-processing to native; ask first.
- **A thin own plugin instead of `flutter_onnxruntime` is the better native
  investment**, if the channel cost proves large on the phone: one call per
  page (image in, boxes and text out, with detection, crops and recognition
  inside) would remove the `detXfer`/`recXfer` shares (18% to 29% here) and
  could overlap recognition runs. It is a bigger step than Rust
  pre/post-processing and also needs the user's go-ahead.
- **Defaults to start from** (the starred ones are settled by the phone
  numbers): typed-list loops; ArgMax recognition model; native decode with a
  maximum side of 2560; detection 960; everything but the decode in a
  background isolate; **threads 4 \***; **provider CPU \*** (XNNPACK/NNAPI only
  with a clear gain); **recognition batch 1 \*** (4 if the phone gains 10% or
  more, accepting about 0.3 points of CER).
- **Expected effect** on the emulator: the final configuration is 10% to 41%
  faster than the Phase 1.5 pipeline (the camera-size images gain most) at the
  same accuracy within the guard. On the phone the 4999 ms of the dense page
  will come down by at least the decode and Dart shares; whether it reaches
  4 s depends on `recRun`, which only the thread/provider/batch choices (and
  the model itself) influence.

### 9.6 UX recommendation: hide the latency

- **Preload the models** when the camera screen opens (create the sessions in
  the background isolate). Loading takes about 0.2 s here and removes the
  cold-run penalty from the first page.
- **Pipeline the pages:** run OCR of page N in the background isolate while
  page N+1 is being photographed, and keep the extracted text with the page.
  With two or three pages the user waits only for the last one.
- **Show progress, not a spinner of unknown length:** the number of boxes is
  known after detection (about 0.1 to 0.3 s), so "line 12 of 51" is possible.
- **Never decode on the UI isolate** (the baseline stalls it for half a second
  per 12 MP photo); OCR must not delay the shutter or the next capture.
- If the phone shows that the camera preview and OCR compete for the CPU,
  start OCR of page N only when the shutter has finished, not during focusing.

### 9.7 Open questions (Phase 1.6)

1. The phone's warm times per scenario and per experiment (threads 1, 2, 4, 6,
   8; XNNPACK; NNAPI; no spinning; detection size; batch; native decode;
   isolate; `final` against `final_b1`).
2. If the dense page stays at 4 to 5 s on the phone, is it `recRun`? Then only
   a smaller or faster recogniser, another provider or fewer lines (merging
   boxes, skipping empty ones) can help; none is proposed yet.
3. Is a thin own plugin worth it (9.5), or is the plugin's per-call cost small
   enough on the phone?
4. Quantisation of the convolution layers (needs calibration images and a
   repeat of the accuracy guard) belongs to the same model-provenance decision
   as open question 5 above (official-model conversion).
5. The user's own hard sample runs through `baseline` and `final`; only numbers
   come back (no accuracy, by design).

## 10. Phase 1.6b: controlled measurements (UI load, providers, accuracy)

Labels: **[phone]** = numbers the user sent from the Xiaomi Note 14 Pro 5G;
**[emulator]** = x86 emulator `Claude_Code_Test`, only good for correctness and
for checking that the tooling works. Phone measurements for A, B, C and D are
**pending** (`PHASE_1_6_VALIDATION.md`).

### 10.1 What the phone showed [phone]

One real receipt (3060x4080, 26 boxes), cold surface, no charger, one run of
the matrix in the order of `perfExperiments`. Warm `recRun`, ms:

| Experiment(s) | `recRun` | UI frames during the cell |
|---|---|---|
| base | 1536 | about 700 to 1200 per 10 s |
| th1 / th2 / th6 / th8 | 1776 / 1359 / 1639 / 2135 | same |
| xnnpack / nnapi / nospin | 1209 / 1161 / 1287 | same |
| batch4 / batch8 | 1478 / 1288 | same |
| fast, nat, nat2560, nat1600, am, iso | **733 to 772** | **1 frame per 9 s** |
| iso_fast / final / final_b1 | 1100 / 1820 / 1174 | same as the first rows |

(det640: total 1983 ms against 2865 for base, detRun 161 against 438, same 26
boxes.) The `recRun` splits into two clusters, about 740 ms and 1100 to 1800 ms.

### 10.2 What differs between the clusters (from the code)

The fast cluster is the contiguous run of experiments `fast, nat, nat2560,
nat1600, am, iso`. They do not share a setting: typed loops (`fast`), native
decode (`nat*`), the ArgMax model (`am`) and the isolate (`iso`) are four
different changes, all with the same threads (4), provider (CPU default), batch
(1) and the same recognition code path. Combinations of them are **not** fast:
`iso_fast` (isolate + typed loops) and `final` (all of them) fall back into the
slow cluster, so no configuration feature explains the split. What does separate
the clusters is the **UI frame count**: in the fast cluster the screen produced
about one frame per 9 s, in the others 70 to 120 frames per second (the always
spinning indicator). Two things differ at the same time there and are
confounded in this data: (1) the UI drawing at the full frame rate, (2) the
position in time (a contiguous stretch of the run, so heat, battery state and
background activity also changed together with it). The near-zero frame count
also means the screen was probably off or the app was not in the foreground
during that stretch, because the spinner was running as usual before and after
it; the app does not hold a wake lock, so a short screen timeout is a likely
cause. Nothing in the data separates "UI load" from "screen off" or from
temperature.

### 10.3 What was added to test it (spike only)

- **UI load switch** on the Perf page: `max` (spinner at the display refresh
  rate; the rate is printed), `still` (nothing animates) and `1 fr/s`. The
  default is `1 fr/s`, what a processing screen would do.
- **A: UI-load A/B.** One fixed setting (native decode 2560, ArgMax model,
  typed loops, batch 1, isolate, 4 threads, CPU), one image, the isolate engine
  kept loaded, 2 unrecorded warm-up runs, then 5 warm runs per state in the
  order max, still, low, low, still, max with a pause (30 s on the phone) at
  `still` between the blocks. Per run: total, `recRun`, `detRun`, frames, and
  the battery temperature when readable. The summary prints block means,
  pooled means and medians per state, the effect (max against still, low
  against still) and the drift between the first and the last visit of the same
  state. The frame monitor is the light one (frame callbacks only, no timers or
  channel pings), so that the instrument adds no load of its own.
- **B: provider x threads.** Threads {2, 3, 4} x provider {CPU, XNNPACK,
  NNAPI}, spinning off, same fixed setting, 3 scenarios, cold run plus 3 warm
  runs per cell, two repeated cells at the end (`_ctl`) as a noise and drift
  estimate. It uses the UI load selected on the page.
- **C: provider accuracy.** The CPU result is the reference; a second CPU run
  gives the noise floor; XNNPACK and NNAPI are compared line by line (boxes
  matched by overlap of at least 0.5): boxes, share of identical lines, mean
  character distance per line, unmatched and extra boxes, mean confidence
  change. Then the synthetic set (10 documents x 4 conditions) runs through all
  three settings (CER, key tokens). Images: the three synthetic scenarios plus
  the user's receipt and hard sample if picked (numbers only). The result is
  also used to exclude a provider from "best" if its results differ.
- **D: best.** Runs the best setting (the fastest grid cell that beats CPU/4
  threads by more than the measured noise, at least 5%, and is not excluded by
  C; before B and C have run, the provisional th4/CPU/spinning off) on the three
  scenarios at native and 12 MP size and on the picked samples.
- The plugin does not report which provider a session really used (an
  unsupported operator falls back to CPU), so the available providers are
  printed and timing plus result differences are the only evidence.

### 10.4 Tooling check [emulator]

- A, with the spinner at full frame rate against `still`/`1 fr/s`, on the
  emulator (software rendering, host CPU shared): pooled `recRun` max 1954 ms,
  still 747 ms, low 752 ms (+161% and +0.7%); total 2999 / 1389 / 1372 ms.
  The first and last visit of `max` were 2156 and 1751 ms, of `still` 742 and
  752, of `low` 727 and 777 (drift of the quiet states within 7%). This
  reproduces the two clusters of 10.1 (about 740 ms against 1.8 to 2.0 s), but
  on the emulator the UI is drawn by the CPU that also runs the model, so it
  shows the tool works and that the effect can be large, **not** that the phone
  behaves the same (the phone draws on the GPU).
- B finished (11 cells; the repeated cells differ from the first ones by 3% to
  5%, so differences between cells below that are noise on the emulator); C
  reported XNNPACK and NNAPI identical to CPU (147/147 lines on 3 images,
  CER 1.8%, keys 156/160 on the synthetic set). On the emulator this says
  nothing about the phone: the providers may not have been active.
- The battery temperature is **not readable** by the app on the emulator
  (`/sys/class/power_supply/battery/temp` is readable by `adb shell`, not by
  the app) and may be unreadable on the phone too; then it prints `n/a`.
  A few lines of Kotlin (BatteryManager through a method channel) would give
  it; that is native code, so it is not done without approval.

### 10.5 Provisional guidance for Phase 2 (to be confirmed on the phone)

- **Do not show a continuously animating spinner while OCR runs.** Use a static
  or very slow indicator and text progress ("line 12 of 51"). This costs
  nothing, and the emulator and the phone's cluster pattern both point to
  animation competing with recognition. The size of the effect on the phone is
  what A measures.
- Threads, provider (CPU, XNNPACK, NNAPI) and batching stay open until B and C
  have phone numbers. In the phone data of 10.1 the differences between the
  slow-cluster values (th2 1359, xnnpack 1209, nnapi 1161, nospin 1287 against
  base 1536) are within the spread caused by the UI-load confound, so they are
  not conclusions.
- A provider is adopted only if C shows results identical to CPU (or a
  difference that the accuracy guard accepts).

### 10.6 Open questions (Phase 1.6b)

1. Phone A: does the UI load change `recRun`, by how much, and does the quiet
   state also drift with time (heat)?
2. Phone B and C: is any provider or thread count faster by more than the
   noise, and does it change the results?
3. Is a tiny Kotlin channel for battery temperature (and a wake lock to keep
   the screen on during a study) acceptable? Without it the user sets the
   screen timeout by hand (`PHASE_1_6_VALIDATION.md`).
4. Language packs: `OCR_LANGUAGE_PACKS.md`.

## 11. Phase 1.6c: the crash on the phone, a safe harness, order effects, language packs

Labels as in section 10: **[phone]** = numbers from the user's phone,
**[emulator]** = x86 emulator `Claude_Code_Test` (2 GB RAM, software
rendering). Phone numbers for the repeated A to D are still pending.

### 11.1 Why the spike was closed by the system

What the phone showed [phone]: during the user's 200 MP sample (12240x16320) the
cells `base` and `th*` had `dec` about 8 s and a UI-isolate stall of about 8 s,
then Android showed repeated "not responding" dialogs and closed the app; the
last copied line was `th1 your_hard_sample`.

What the code does: every experiment of the groups `baseline`, `ort`, `det`,
`batch` and `pre` decodes the JPEG in pure Dart **on the UI isolate**
(`config.isolate == false`), and a cell decodes the image four times (one cold
and three warm runs). For this sample that is about 4 x 8 s of a frozen UI per
cell, one cell after the other. The group `decode` experiment `nat` (native
decode at full size) needs 12240 x 16320 x 4 bytes = about 800 MB for the
bitmap alone.

Reproduction attempt [emulator, 2 GB]: the harness with the guard switched off
(`--dart-define=UNSAFE=true`, kept only for this) on a generated 200 MP JPEG
(synthetic text, 9 MB file):
- the UI isolate stayed blocked: `Choreographer: Skipped 3664 frames` in one
  report, no finished cell after more than 6 minutes (in a first attempt more
  than 30 minutes; at the end `adb shell` no longer answered and the emulator
  had to be killed and restarted);
- the system ran out of memory: within 30 s of the start the low-memory killer
  killed about ten other processes (`reason: low watermark is breached`) and the
  swap filled;
- **not reproduced:** an ANR record for the app, or a kill of the app itself. The
  app's own memory when I looked was small (RSS 69 MB, peak 226 MB, 76 MB in
  swap), so the "0.8 to 1.6 GB" estimate for the Dart decode is **not
  confirmed** by this run; what was seen is that the system as a whole was
  starved while the decode ran. A 2 GB emulator is not a 12 GB phone, so this
  says nothing about which of the two (ANR or memory kill) closed the app.

Verdict: **confirmed** that the old harness blocks the UI isolate for the length
of every Dart decode (8 s per run on the phone, above the 5 s that Android
allows for a pending input event) and that a full-size decode of such an image
is very expensive in memory; **not confirmed** which one ended the process. The
new APK asks Android for the exit reason of the previous process
(`ApplicationExitInfo`: ANR, LOW_MEMORY, CRASH, ...) and prints it at the next
start, so the next crash will be classified by the system.

Follow-up (start of Phase 2): the user ran the safe harness on the phone and
reported that the phone tests **confirmed the hypothesis about very large
photos** (the whole-image Dart decode of a huge photo is what brought the old
harness down). No numbers or exit reasons were sent with that message, so the
split between "not responding" and "killed for memory" is still not recorded
here. Phase 2 therefore applies a ceiling to the photo input (ADR-014: header
read first, nothing decoded above 50 MP, native decode with `inSampleSize`
above 8 MP, never on the UI isolate).

### 11.2 The safe harness (spike only)

- **Size guard from the file header** (`sample_guard.dart`, JPEG/PNG header,
  nothing decoded): a full-size decode (Dart decode, or native decode without
  a cap) of an image above 50 MP is skipped with the line `skipped (would
  exceed memory budget: 200 MP, limit 50 MP for a full-size decode)`; a Dart
  decode above 20 MP is moved to the background isolate. Native decode capped
  at 2560 px is always allowed.
- **Result** [emulator, 200 MP]: `base`, `th1`, `fast`, `nat` skipped;
  `nat2560` ran: decode 326 ms, 48 boxes, UI stall 109 ms, process memory 224 MB
  after and 511 MB peak.
- **Breadcrumb** (`run_log.dart`): before every cell its id is written to a file
  in the app's own directory, after it the result line; only ids, timings and
  counts. At the next start a red box says in which cell the run was cut and
  what Android recorded for the previous process, the saved lines are listed
  and included in "Copy summary", and **Resume** continues with the next cell
  (matrix, picked samples, grid, best).
- **Screen kept on** with `wakelock_plus` while a step runs; **battery
  temperature** through a small Kotlin method (`BatteryManager`), printed per
  plan and between groups (`25.0 C` on the emulator; `n/a` where the system
  gives none); **memory** (`mem rss .. peak ..` from `/proc/self/status`) in
  every cell line; **rest** of 20 or 30 s between groups; one unrecorded
  **settling run** between the cold run and the warm runs (the warm figure is
  now the mean of the three runs after it; older figures had no settling run).
- Everything the studies print also goes to the log file, so nothing is lost if
  the app is closed.

### 11.3 The two clusters, again

Phone numbers sent after 1.6b [phone], `recRun` in ms, UI load `1 fr/s`:
`base` 1029 (with UI load `max` it was 1536); the groups `fast`, `nat*`, `am`,
`iso_fast`, `final_b1`, `det*` 740 to 810; batch 4 and 8 1092 to 1325; `final`
(batch 4) 1103 against 773 for `final_b1`; XNNPACK 898 and NNAPI 829.

What can and cannot be said:
- **UI load** matters on the phone too: the same `base` cell fell from 1536 to
  1029 ms (-33%) by lowering the UI load (not controlled for heat).
- **Batch** now explains the slow cells of `batch` and `final`: batch 4 or 8
  is 40% to 70% slower than batch 1 on the phone (padding: a batch is as wide as its
  widest line). Use batch 1.
- **Providers:** XNNPACK (898) and NNAPI (829) do not beat the 740 to 810 of the
  fast cells; the earlier apparent gain came from the slow `base` cell they
  were compared with. No evidence for either; keep CPU.
- **The first group looking slow (`base` 1029 against about 770):** not an order
  effect on the emulator and probably not on the phone. The paired test (A B,
  B A, ... in one run, `runPairedAB`) on the emulator gave:

  | Comparison (6 rounds each) | `recRun` of B against A |
  |---|---|
  | control: the same setting twice | +2.2%, -2.7%, +6.0% in three runs (noise about 6%) |
  | engine in the **root isolate** (A) against background isolate (B) | **-29.3%** (1347 against 953 ms) |
  | Phase 1.5 pipeline (A) against the study setting (B) | -25.3%, -20.0% in two runs |
  | ArgMax model off (A) against on (B) | +13.9% (B slower, within what the control shows) |
  | batch 1 against batch 4 | +5.8%, +7.1%, +28.8% (emulator, not consistent) |
  | batch 1 against batch 2 | -10.0%, +3.3%, -7.0% |

  The drift inside a run (first third against last third) was +-5% to +-20%
  even for the control, so a single run of one setting after another cannot
  show differences below that. The slowdown follows **where the engine runs**
  (root isolate against background isolate), not the model variant and not the
  position in the sequence. A possible mechanism (not tested): `recRun` is the
  wall time of an awaited plugin call, and in the root isolate the reply has to
  wait for the same event loop that also draws frames and runs the Dart pixel
  loops. If true, it is a measurement and a scheduling effect of the root
  isolate, not slower inference. The phone must repeat the paired test (step F
  of `PHASE_1_6_VALIDATION.md`).

### 11.4 Re-run of B, C and D on the emulator (tooling only)

Grid with two passes (forward, backwards): the cells differ by 2.8% between the
passes (margin to leave CPU/4 threads: 5.6%); XNNPACK and NNAPI results were
identical to CPU on 147 lines and on the synthetic set (CER 1.8%, keys
156/160). The available providers were `CPU, NNAPI, XNNPACK`. None of this
says anything about the phone: the grid's "best" on the emulator was an
NNAPI/2-thread cell inside the noise, which is exactly what the margin rule
exists to prevent on the phone.

### 11.5 Language packs

Measured on invented documents (accuracy does not depend on the device); full
table in `OCR_LANGUAGE_PACKS.md`: plain English CER 0.1% to 0.2% with all three
packs; mixed Greek + English only readable with the Greek pack (CER 2.9%, the
Latin pack 26.0%), with Latin-code confusions; accented Latin letters of de,
fr, es, it, pt kept 284/284 with the Latin pack (CER 0.0%), 0/284 with the Greek
pack, 99/284 with the East Slavic pack.

### 11.6 Provisional recommendation for Phase 2 (to be confirmed on the phone)

- Run the engine in a **background isolate**, decode natively capped at 2560 px,
  recognition **batch 1**, **CPU** provider, no continuously animating spinner
  during processing, progress as text.
- Threads (2, 3 or 4) stay open until B on the phone has two passes of data.
- Never decode a full-size photo of unknown size in Dart: read the header,
  cap the decode.

### 11.7 Open questions (Phase 1.6c)

1. The exit reason Android gives for the phone crash (if it recurs).
2. Phone paired test: is the root isolate slower there too (about 40% in
   `recRun`), and is batch 1 always better?
3. Phone grid with two passes and the provider accuracy check.
4. Whether to measure the official English-only recogniser against the Latin
   pack, and real (not invented) mixed Greek + English scans.
