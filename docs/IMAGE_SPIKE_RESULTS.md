# Image spike results (Phase 6.0)

Status: **spike 6.0 complete (2026-10-31): sections 1 to 9 are measured on the emulator and the PC, and the phone check by the user is in the appendix at the end.** The decisions that followed (A3 only, enclosing quad, confidence 0.5, originals untouched) are the base of Phase 6.1 (`DECISIONS.md` ADR-029).

Section 1 below was written first, from pages fetched on 2026-10-29 (research before anything was built). The other sections are measurements.

All claims of section 1 come from pages fetched on 2026-10-29. "Not stated" means the page
was read and does not say it; it is not a statement that the thing is false.

## 1. Implementation options

### (B) ML Kit Document Scanner (Google): not a candidate for our flow

Source: https://developers.google.com/ml-kit/vision/doc-scanner/android (page "Last
updated 2026-10-28 UTC").

| Question | What the page says |
|---|---|
| Own screen or our image? | "The document scanner user flow (which includes a dedicated viewfinder screen and preview screen) is provided by the SDK." It is started with `getStartScanIntent(activity)` and read back with `GmsDocumentScanningResult.fromActivityResultIntent`. **No API to pass an existing image or our own camera frames is documented.** Gallery import exists only as a control inside its own flow (`setGalleryImportAllowed`). |
| Delivery, network | "The models, scanning logic and UI flow are dynamically downloaded by Google Play services." "Users might have to wait for the models, logic and UI flow to download before first use." So it needs Google Play services and a download at first use (this conflicts with ADR-001 unless the user accepts it). |
| On device? Privacy? | **Not stated** on this page. It links to "Android Data Disclosure" and the ML Kit terms, which were not read. |
| Limits | Android API 21 or above; minimum total RAM 1.7 GB, otherwise `MlKitException` with `UNSUPPORTED`; about 300 KB app size. |
| Results | JPEG pages and PDF, page limit settable; modes: only `SCANNER_MODE_FULL` appears, the others are not listed on the page. |
| iOS | The page is Android only; no iOS statement. |

**Conclusion:** it forces its own capture screen, so it cannot sit inside the One
Click flow or our CameraX abstraction, and it depends on Play services and a model
download. It is **not a candidate for integration**. It was not built, as the request
allows. Not verified: whether it runs fully on device (needs the data disclosure page).

### (A) Own implementation with classic algorithms

#### A1. OpenCV from Dart: `opencv_dart` / `dartcv4`

Sources: https://pub.dev/packages/opencv_dart (2.2.2, "published 2 months ago", no
exact date on the page), https://pub.dev/packages/dartcv4 (2.3.1, "41 days ago"),
the changelog of opencv_dart.

- **License:** Apache-2.0 (full text on the license page). No GPL/AGPL. OpenCV itself
  is Apache-2.0 from 4.5.0 (see A2).
- **Platforms:** Android, iOS, Linux, macOS, Windows, all "Supported and Tested".
  Android ABIs x86_64, arm64-v8a, armeabi-v7a. So a future iOS is covered.
- **Requirements:** Dart 3.10 (Flutter 3.38) or newer, because it uses native assets
  and hooks. The app is on `sdk: ^3.13.5`, so this is met.
- **How the native code arrives:** since 2.2.0 "support building from opencv source
  code, it's now the default behavior ... prebuilt opencv static binary is no longer
  included" (4.12.0 was the last prebuilt). So **OpenCV is compiled from source at
  build time with CMake** (build time and toolchain become part of the project).
  The OpenCV version pinned by the package is not stated on the page (the 2.2.0
  changelog says 4.13.0).
- **Modules:** `core`, `imgproc` and `imgcodecs` are on by default; the rest are off
  (calib3d, features2d, dnn, objdetect, photo and others). This keeps the binary
  smaller. `treeshake` exists and is off by default.
- **Not confirmed from these pages:** that Canny, findContours, getPerspectiveTransform,
  warpPerspective and CLAHE are bound (imgproc is bound, the list of functions was not
  read); the APK size increase; 16 KB page size and NDK for 2.x. These are measured
  in the spike with a release build.
- **Maintenance risk:** one maintainer (publisher rainyl.dev); "Problems that come from
  a non-default OpenCV are not supported". A native build from source adds build risk.

#### A2. OpenCV official Android library in Kotlin

Sources: Maven Central listing and POMs (https://repo1.maven.org/maven2/org/opencv/opencv/),
https://central.sonatype.com/artifact/org.opencv/opencv.

- **License:** POM of 5.0.0 and 5.0.0.1: `Apache-2.0`. A separate search result (an
  OpenCV Q and A quote and the opencv.org announcement title) says 4.5.0 and later
  are Apache 2. **The opencv.org license page and the announcement returned 403, so
  the exact wording and the note about contrib or non-free modules are not verified.**
- **Versions:** newest upload 5.0.0.1 (2026-06-26); 4.14.0 (2026-07-21); 4.13.0
  (2026-01-22). Maven metadata `latest` still says 5.0.0.
- **Size:** `opencv-5.0.0.1.aar` is 153,027,846 bytes (about 153 MB) for all ABIs
  and all modules. The per-ABI `.so` size is not stated. With `abiFilters arm64-v8a`
  and R8 the APK increase will be much smaller, to be measured. This is the main
  cost of this route.
- **iOS:** this route is Android only (Kotlin). A future iOS needs a second
  implementation, which is a point against it.
- **How to use:** Gradle coordinate `org.opencv:opencv:<version>` (the official Android
  tutorial page returned 403, so module selection is not verified).

#### A3. Pure Dart/Kotlin without OpenCV (typed loops, as for the OCR)

- No new dependency, no licence question, no APK increase beyond code. The `image`
  package is already a dependency of the app and the spikes (MIT,
  checked on pub.dev 2026-10-30, see the licence table below).
- Cost: we write and maintain grayscale, blur, Canny, contours, quadrilateral
  fitting, homography and warp ourselves; speed on 12 MP must be proven (the OCR
  work found typed loops in Dart acceptable, see ADR-010). Pure Dart is portable to
  iOS.
- Work already known from the OCR spike: decode to a small working size first
  (ADR-014), so detection at about 1 MP is the realistic budget.

### Third option, recorded only (not built)

None found in this research beyond the above. Not searched exhaustively
(for example OpenCV-based document scanner packages on pub.dev, or an ONNX
segmentation model for document corners, which we could run with the existing
`flutter_onnxruntime`). **Not implemented; ask the user first.**

### Summary table

| Option | Licence | Size cost | iOS later | Own camera/flow | Main risk |
|---|---|---|---|---|---|
| ML Kit Document Scanner | ML Kit terms (not read) | about 300 KB + Play services download | not stated | **No**, own screens | Not usable in our flow |
| A1 `opencv_dart` | Apache-2.0 | to measure | Yes | Yes | Build from source, one maintainer |
| A2 OpenCV Android AAR | Apache-2.0 (POM) | AAR 153 MB, to measure after ABI filter and R8 | No | Yes | Android only, size |
| A3 Pure Dart | none | code only | Yes | Yes | Our own maintenance, 12 MP speed |

## Licence check from the repositories (2026-10-30)

The opencv.org pages refused automatic fetching (403), so the licences were checked
in the repositories and on pub.dev, as decided by the user.

| Component | Source | Result |
|---|---|---|
| OpenCV | https://raw.githubusercontent.com/opencv/opencv/master/LICENSE and `/4.x/LICENSE` (identical, fetched 2026-10-30) | Apache License 2.0, January 2004. The file is the standard text, with no notes on third-party code or non-free modules. |
| OpenCV third-party code | `3rdparty/readme.txt` on branch 4.x (2026-10-30) | Names libjpeg, libjpeg-turbo, libpng, libspng, libtiff, zlib, zlib-ng, jasper, openexr and ffmpeg. It gives no licence type for most of them and sends the reader to each library's own LICENSE. **ffmpeg is the one to watch (LGPL/GPL in general); its file `3rdparty/ffmpeg/readme.txt` was not read.** `opencv_dart` 2.x does not include ffmpeg since 2.2.0 (changelog, 2026-10-29), and the default modules are core, imgproc and imgcodecs only. The licences of the bundled image codecs are still to be listed from the real build (a task of the spike, with the APK). |
| `opencv_dart` | https://raw.githubusercontent.com/rainyl/opencv_dart/main/LICENSE and the package page on pub.dev (2026-10-29/30) | Apache License 2.0 in both. |
| `image` (A3) | https://pub.dev/packages/image and `/license` (2026-10-30) | Version 4.12.0, published 18 days before the check, publisher taosengine.com, **MIT** (Copyright 2013-2022 Brendan Duncan). Repository: https://github.com/brendan-duncan/image. |

This replaces the sentence in A2 about the licence being unverified: the OpenCV licence
is now confirmed from the official repository. The Maven POM (Apache-2.0) agrees.

## Decisions of the user (2026-10-30)

- **Built in the spike: A1 (`opencv_dart`) and A3 (pure Dart).**
- **A2 (OpenCV Android AAR) is not a candidate:** Android only, and it duplicates A1 on
  Android.
- **ML Kit Document Scanner is not a candidate:** it does not take our image or our
  camera frames, it forces its own screens.
- The ML Kit "Android Data Disclosure" page and the ML Kit terms were **not read**, by
  decision: they cannot change the conclusion above.

## 2. Spike project and synthetic generator (2026-10-30)

Project: `spikes/image_spike/` (option (a): separate project; the main app, its
`pubspec.yaml`, Manifest and Gradle are untouched). Dependencies: `opencv_dart`,
`image`, `path_provider`, `vector_math`.

### Feasibility of A1 (`opencv_dart` 2.2.2), measured

- The binding has the functions the spike needs (the analyzer accepts `canny`,
  `findContours`, `getPerspectiveTransform2f`, `warpPerspective`, `createCLAHE`).
- **`flutter build apk --release --target-platform android-arm64` of a nearly empty
  app that only references them: succeeded, 312 s (5 min 15 s total) on this PC,
  because OpenCV is compiled from source (the first build; later builds should be
  cached). APK 26,043,372 bytes (24.8 MB).**
- That size has **no baseline yet** (an empty Flutter release APK for the same ABI
  was not built), so the cost of OpenCV is not known. To be measured next, together
  with the licences of the codecs bundled by the build.

### Generator

- `lib/src/geometry/` (quad, IoU, coverage of the true page, corner error,
  homography) and `lib/src/synth/` (documents, scene renderer, dataset), pure Dart.
- Four invented flat pages (`assets/synth/pages/`, Noto Sans): Greek receipt, English
  receipt, Greek water bill with an RF code and an IBAN-shaped number, dense English
  leaflet. Names, codes and amounts are made up; addresses are `@example.com`.
- The pages are placed in a 1536 x 2048 frame through a real 3D projection (tilt about
  both axes, roll, distance), so the **true outline is exact** (written to the
  manifest). Added: table, dark, line-pattern and cluttered backgrounds, drop shadow,
  uneven light and a shadow band, low contrast, surface waves (crumple, the outline
  is the flat page's nominal one), a hand-coloured blob over an edge, noise, a page
  leaving the frame, a page covering the frame, a small page, and scenes with no page.
- **77 scenes**, fixed seed (20261030), 15 categories: frontal 4, perspective 6
  (10, 20, 30 degrees), rotation 6 (5, 10, 15), light 6, low contrast 5, crumple 6,
  noisy background 6, hand 4, dark background 5, partial 5, fills frame 3, small
  document 5, lines background 6 (hard), no document 4 (hard negatives), combined 6.
- Generation: `flutter test tool/render_flat_pages_test.dart`, then
  `flutter test tool/generate_dataset_test.dart` (161 s for 77 scenes) writes
  `build/synth/*.jpg`, `manifest.json` and `contact_sheet.jpg` (not committed).
- Unit tests: 25 (geometry, homography, determinism of the render, truth outline,
  rotation angle, partial and fills-frame flags, no-document scenes, dataset
  coverage). `flutter analyze` clean.

Known limits of the synthetic set: the hand is a flat-coloured blob, the crumple is a
smooth wave (no sharp creases), backgrounds are procedural, the "real" difficulty of a
phone photo (focus blur, JPEG, lens) is only approximated by noise. Results on it say
how the detectors compare, not how they will do on real documents (the phone check
with the user covers that).

## 3. Detectors A1 and A3 on the synthetic set (2026-10-30)

### What was built (`spikes/image_spike/lib/src/detect/`)

Both detectors take an RGB frame and return the best candidate outline plus a
confidence; the caller applies a threshold (below it, the PDF gets the whole frame).

- **Shared (Dart):** grey and area-average downscale to a 640 px working picture, 5-tap
  blur, Otsu levels, the enclosing-quad reduction, the confidence score. Outlines are
  scaled back to the frame.
- **Candidates (two sources):** (1) edges: Canny, close gaps (3x3 dilation), connected
  pieces, hull of each big piece; (2) brightness: Otsu (paper is the bright class) and
  Otsu again inside the bright class, connected pieces, hull. Up to 6 pieces per source.
- **A3, pure Dart:** all pixel work on typed lists (Sobel, non-maximum suppression,
  hysteresis, dilation, erosion, flood fill).
- **A1, OpenCV (`opencv_dart` 2.2.2):** blur, Canny, dilate, erode, threshold, findContours.
  Two ways to get four corners from a hull: **approxPolyDP** (the usual OpenCV way) and
  the **enclosing quad** of A3.
- **Enclosing quad:** the polygon is reduced to four corners by replacing the two
  vertices of the edge that costs the least extra area with the point where the
  neighbouring edges meet. The result always contains the hull, so it cannot cut
  the page (it can be a little loose).
- **Confidence (0..1):** `min(area, angle, ratio) * support * (0.5 + 0.5 * contrast)`.
  `area`: plausible share of the frame (0 below 5%, 1 from 20%, 0 above 97%).
  `angle`: corners within 25 degrees of a right angle (perspective allowed), 0 at 50.
  `ratio`: opposite sides within 0.45 to 0.7 of each other. `support`: share of samples
  along the four sides that have a strong gradient within 3 px (samples near the frame
  border are not judged, the page may continue outside). `contrast`: median
  difference of grey 5 px inside and outside the outline.
- **Outcome at a threshold** (against the visible part of the true page): *fallback*
  (not trusted, whole frame), *good* (used, nothing cut, IoU 0.9 or more), *loose*
  (used, nothing cut, IoU below 0.9), ***cuts content*** (used, more than 2% of the visible
  page outside the crop: the "surely wrong" case), *false positive* (used on a picture with
  no page).

### Results (Claude_Code_Test emulator, x86_64, **release** build, pictures at 768 x 1024)

77 pictures, 73 with a page. Raw = best candidate with no threshold, pages only.

| | A3 pure Dart | A1 OpenCV, approxPolyDP | A1 OpenCV, enclosing quad |
|---|---|---|---|
| IoU 0.9 or more (raw) | 89.0% | 94.5% | 89.0% |
| Nothing cut (raw) | 95.9% | 91.8% | 95.9% |
| Median IoU (raw) | 0.977 | 0.986 | 0.973 |
| Median corner error, % of the diagonal | 0.45 | 0.27 | 0.49 |
| **Cuts content at threshold 0.5** | **0** | **4** | **0** |
| Cuts content at threshold 0.1 | 0 | 5 | 0 |
| Cuts content at threshold 0.0 (always use) | 3 + 4 false positives | 6 + 4 | 3 + 4 |
| Good at 0.5 / loose / fallback | 61 / 2 / 14 (18.2%) | 59 / 0 / 14 (18.2%) | 61 / 2 / 14 (18.2%) |
| Time, median (p95) per picture, ms | 64.8 (99.7) | 20.6 (31.9) | 19.9 (31.9) |
| of which detect (median) | 52.0 | 8.0 | 7.8 |

(The shared grey downscale takes about 11 ms and the confidence about 0.6 ms in all three.)

**Findings**

1. **The enclosing quad is what keeps the PDF from losing content, not the library.**
   With approxPolyDP, OpenCV cut 3 to 4 pages at high confidence (page coverage 92% to
   97%; in `noisy_background`, `hand` and `lines_background` scenes, scores 0.92 to
   1.00), so confidence alone did not catch them. With the enclosing quad both A1
   and A3 had **0 cuts at every threshold from 0.1 to 0.9**.
2. **The confidence separates well on this set.** With A3, every wrong or false
   detection scored 0.138 or less, and almost all good ones 0.955 or more. Any
   threshold between 0.2 and 0.9 gave 0 cuts and 0 false positives. Between 0.3 and 0.7
   nothing changes; a threshold of **0.5** leaves the largest margin on both sides.
3. **Cost of safety:** 14 of 77 pictures (18.2%) fall back to the whole frame at 0.5.
   Of these, 4 are pictures with no page and 2 are pages that fill the frame (the
   fallback is the right answer for these 6). The other 8 are real misses: all 5
   `small_document` (the `area` part is below 0.2 by design, median IoU of the raw
   detection 0.91 to 0.96, so the outline was found) and 3 of the 6 `combined` scenes.
   Lowering the minimum area would crop small receipts too; that is a product choice.
4. **Speed:** OpenCV is about 6.5 times faster in the detect step (8 ms against 52 ms)
   and about 3.2 times in total (20 ms against 65 ms) on this x86 emulator, for a
   768 x 1024 picture (640 px working size). The cost is the native build (see section
   2) and an unknown APK increase. Both are below the roughly 1 s per page of the OCR.
   Phone timings are still to be taken (arm64, same APK).

### Limits

- Synthetic pictures only, from the generator of section 2 (clean paper, procedural
  backgrounds, no focus blur). The perfect separation of the confidence is a result on
  77 pictures, not a guarantee; real documents (creased receipts, glossy paper,
  paper on paper) are the point of the phone check.
- "Cuts content" uses a 2% tolerance on the visible area of the true outline; crumpled
  pages are judged against the flat page's outline.
- The comparison used half-size pictures (768 x 1024) so the dataset fits in the APK
  (11 MB of assets, `assets/eval/`). The same A3 on the PC at full size (1536 x 2048)
  gave the same decisions at threshold 0.5 apart from one `light` picture; its median
  total was 88 ms in debug mode.
- Timings are from an x86_64 emulator on this PC, not a phone.
- Not done yet in this step: OCR gain (CER and word count before and after the crop),
  the OCR-based safety check after the crop, contrast options, background processing,
  reading order, focus, the phone screens.

## 4. OCR gain, safety check and reading order (2026-10-30)

### Method

- **Engine:** the real OCR of the app (PP-OCRv5 through ONNX Runtime, in its background
  isolate), as a copy in `spikes/image_spike/lib/ocr_copy/` made by `tool/sync_ocr_code.sh`
  (the commit of the main app it came from is in `SOURCE.txt`; the models are not in git).
  Packs: `greek` for the Greek pages, `latin` for the English ones.
- **Pictures:** the 77 scenes of section 2 at full size (1536 x 2048), plus 6 new scenes
  of a two-column receipt tilted 0, 5, 10, 15, -10 and -15 degrees (section 4.5). 79 of
  the 83 have a page and were read; the 4 empty scenes were not.
- **Conditions per page:** `frame` (the whole picture, what the app does today),
  `oracle` (the perfect crop from the true outline, only where the whole page is in the
  frame), and the crop of each pipeline when its detection reaches the threshold 0.5:
  **A3** (pure Dart detection and warp), **A3small** (A3 with the area bound lowered to
  1% to 4% of the frame, for small pages), **A1** (OpenCV detection and warp, enclosing
  quad), **A1poly** (OpenCV with approxPolyDP). Identical crops share one OCR (the csv
  column `reusedFrom` says which).
- **The crop:** perspective warp to an upright picture. The proportions of the page are
  recovered from the outline and the camera focal length (the real app would take it
  from the EXIF 35 mm focal length; here the generator value is used), so a tilted
  page is not squeezed (error below 1.5% in the unit tests). Without a focal length the
  mean of opposite sides is used, which makes a page tilted 20 degrees about 6% too narrow.
- **Metrics against the known (invented) text:** CER on text with whitespace collapsed;
  word recall (each known word counts once); key-token recall; reading order (share of
  adjacent lines in the right order); label-value pairing. Only the numbers are printed,
  never the text. Release build, x86_64 emulator `Claude_Code_Test` (2 GB RAM); peak RSS
  of the app 652 MB.

### 4.1 Does the crop make the reading better?

Pages where the crop was used, change against the whole frame (final run, 79 pages):

| condition | pages cropped | mean CER frame -> crop | word recall | worse by more than 2 points | OCR time frame -> crop (ms) |
|---|---|---|---|---|---|
| oracle (perfect crop) | 73 | 0.017 -> 0.008 | +0.7 pts | 0 | 1436 -> 995 |
| A3 | 68 | 0.011 -> 0.009 | +0.3 pts | 0 | 1447 -> 1012 |
| A3small | 73 | 0.023 -> 0.013 | +1.0 pts | 0 | 1436 -> 991 |
| A1 | 69 | 0.011 -> 0.009 | +0.3 pts | 0 | 1443 -> 1011 |
| A1poly (approxPolyDP) | 69 | 0.011 -> 0.010 | +0.1 pts | **1** (`noisy_background_38`: CER 0.000 -> 0.072, recall 1.00 -> 0.91) | 1443 -> 995 |

1. **On this clean synthetic set the accuracy gain is small, because the engine already
   reads the whole frame almost perfectly** (mean CER 2.9% over all pages and 0.9% to 1.1%
   on the pages that get a crop; word recall 95.6%). With the enclosing quad a crop never
   made a page much worse, and it did not help much either. The real documents of the
   phone check (blur, shadow, glossy paper) are where accuracy could differ; that is not
   measured.
2. **The clear gains are on small pages and on speed.** `small_document` (page about 10%
   of the frame): CER 0.185 -> 0.071 and word recall 0.71 -> 0.79 with the perfect crop.
   A3 does not crop these (area rule), A3small does (CER over its 73 crops 0.023 -> 0.013).
   `partial` (page leaving the frame) with the perfect crop: CER 0.032 -> 0.002.
   Pages that cover the whole frame (`fills_frame`) have CER 0.31 with or without a
   crop, because part of the page is outside the picture.
3. **The OCR is about 30% faster on the crop** (1447 -> 1012 ms for A3; the crop is
   1.4 MP against 3.1 MP). After the cost of the crop (detection and confidence 86 ms +
   warp 52 ms for A3, 32 + 26 ms for A1, medians) the net saving is about **0.3 s per
   page for A3 and 0.37 s for A1**, on this emulator. At 21 pages that is about 6 to 8 s
   of the 21 s measured in Phase 5.1 (an estimate; not the same run).
4. **The approxPolyDP outline can cut content, as found in section 3:** here one page
   lost 9% of its words at high confidence. The enclosing quad (A1, A3) had no such page.

### 4.2 Detection at full size (1536 x 2048), same emulator

The detection tables of section 3 were taken at 768 x 1024; the same run at full size gave
the same picture (details in `ocr_run5_final_83scenes.log`, `OCREVAL detreport` lines):
A3 0 cuts and 0 false positives from threshold 0.2 up; A1 enclosing quad 0 cuts from 0.2;
A1 approxPolyDP 4 cuts from 0.4 up to 0.9. Median time per picture: A3 79 ms, A1 28 ms
(prepare about 19 ms, the same Dart grey downscale in both).

### 4.3 Confidence and fallback rule (summary of sections 3 and 4)

- **Rule:** use the crop when the confidence is 0.5 or more and the outline comes from the
  **enclosing quad**; otherwise the PDF gets the whole frame. The originals are never
  changed (decision 2 of the request). With this rule: 0 pages cut and 0 false positives
  on the 77 scenes of the detection tables, and 18% of the pages fall back to the whole
  frame (6 of the 14 correctly: no page, or the page fills the frame).
- **Cost of the small-page option** (area bound 1% to 4%): the 5 small pages are cropped
  (4 tight, 1 loose), but **2 of the 4 empty scenes (a line-pattern or clutter background
  with no page) get a confident crop**, still at threshold 0.7 (one remains at 0.9). With
  no page in the picture nothing of a document is lost, but the PDF would hold a
  meaningless crop. Whether small receipts are worth that risk is a product decision;
  a real-document check is needed before choosing.

### 4.4 Safety check after the crop (measured, final run)

The request: prefer the whole frame when the OCR finds clearly fewer words in the crop.
Measured on the pages where each pipeline cropped. "Lost" = word recall of the crop
more than 2 points below the frame's (against the known text, which the app does not have).

| pipeline | check | crops that lost words | triggered | triggered and lost | triggered, crop was fine | lost and not caught |
|---|---|---|---|---|---|---|
| A3 | word count < 90% | 5 | 0 | 0 | 0 | 5 |
| A3 | word count < 97% | 5 | 1 | 0 | 1 | 5 |
| A3 | frame-text coverage < 95% | 5 | 5 | 0 | 5 | 5 |
| A3 | frame-text coverage < 98% | 5 | 21 | 5 | 16 | 0 |
| A1poly | word count < 90% | 7 | 0 | 0 | 0 | 7 |
| A1poly | frame-text coverage < 95% | 7 | 6 | 2 | 4 | 5 |
| A1poly | frame-text coverage < 98% | 7 | 19 | 7 | 12 | 0 |

(A3small and A1 rows are in the log; they look the same.)

1. **The word-count rule of the request does not work:** it never triggered at 90%, and
   even at 97% it caught nothing real. A crop that cuts through lines leaves broken
   words, which still count as words (`noisy_background_38`: 58 words in the frame, 56 in
   the crop, recall 0.91).
2. **Comparing the content works only with a threshold so strict that it fires on noise.**
   The share of the frame words that the crop also reads catches every loss at 98%, but
   it triggers on 21 of 68 pages for A3, 16 of them with no loss. Most "losses" here are
   one word read differently (recall 1.00 -> 0.97), and the perfect crop has them too:
   they are OCR noise, not cut content.
3. **The cost is the problem.** Both checks need the OCR of the whole frame and of the
   crop: about 1.45 s + 1.0 s per page against 1.45 s today. The check removes the whole
   time gain of the crop (it would be about 1 s slower per page than today) and pays
   for a protection that the enclosing quad and the confidence already give on this set.
4. **Not measured, a candidate for Phase 6:** a check that needs only the OCR of the crop,
   for example "many text boxes touch the border of the crop". Not built or measured.

**Suggestion:** do not run the double OCR by default. Rely on the enclosing quad and the
confidence threshold, and decide the extra check after the phone check shows how
real documents behave.

### 4.5 Reading order and tilt (request 6)

- **Single-column pages tilted 5 to 15 degrees (`rotation`, 6 pages; also `perspective`
  and `combined`):** the reading order is right (1.00) with the whole frame and with the
  crop. In this set there is nothing for the correction to repair.
- **Two-column receipt tilted 0 to 15 degrees (new category `tilted_table`, 6 pages,
  labels at the left, amounts at the right margin, 14 pairs each, including a
  discount line of 0,00 between net amounts, like the real receipt of Phase 2):**
  the share of labels followed by their own value:

| page (roll angle) | frame | perfect crop | A3 | A1 |
|---|---|---|---|---|
| 77 (0) | 0.93 | 0.93 | 1.00 | 1.00 |
| 78 (5) | 0.93 | 0.93 | 0.93 | 0.93 |
| 79 (10) | 0.93 | 0.93 | 0.93 | 0.93 |
| 80 (15) | 0.93 | 0.93 | 0.93 | 0.93 |
| 81 (-10) | 0.86 | 0.93 | 0.93 | 0.93 |
| 82 (-15) | 0.86 | 0.93 | 0.93 | 0.93 |
| mean | 0.905 | 0.929 | 0.940 | 0.940 |

  The engine keeps almost every pair even on the tilted whole frame; the two frames
  tilted the other way (-10 and -15 degrees) lose one more pair than their crops. That is
  one pair out of 14 on two pages, so it is **not a measured improvement, only a hint**.
  The mistake of the real receipt of Phase 2 was **not reproduced** on clean synthetic
  pages. It happened on a blurred photo with a shadow, which the generator does not make.
  The one pair wrong in most conditions is a reading difference, not a tilt effect. The
  real receipt of the phone check is the test that matters.

### 4.6 Memory and the build

- Peak RSS of the app during the evaluation: **652 MB** (models and the two packs,
  one full-size picture at a time, crops up to 3 MP). The 2 GB emulator killed an
  earlier version of the run that kept all 77 pictures in memory.
- **A release build needs the ONNX Runtime keep rule** (`-keep class ai.onnxruntime.**`).
  Without it the first OCR call aborts with SIGABRT (`JNI DETECTED ERROR IN APPLICATION:
  java_class == null`). The main app has the rule; the spike lacked it until this run.
  Any new Gradle module that uses the engine must keep it.

### 4.7 Limits of this section

Synthetic pages only, one OCR engine, one emulator (x86_64) with a 2 GB limit, the focal
length of the generator used as if it came from EXIF, and a focal length of about 1.9 times
the long side (a mild perspective; a phone wide camera has stronger perspective for the
same tilt). Times are the emulator's, not a phone's. Not done in this step: contrast
and shadow options (request 4), background processing while shooting (5), the autofocus
report (7), the APK size baseline, the phone screens and `PHASE_6_0_VALIDATION.md`, the
roadmap update and the Phase 6 proposal.

## 5. Contrast and shadow options (request 4, 2026-10-31)

### Method

- **Options** (pure Dart, `spikes/image_spike/lib/src/image/enhance.dart`, on the upright crop):
  `color` (no change, what the app does), `gray`, `flat` (shadow and uneven light removed:
  every pixel divided by the paper's local brightness, colour kept), `clahe` (adaptive
  histogram equalisation of the brightness, tiles 8x8, clip 2.0), `flat+clahe`, and
  `binary` (flat, then a local mean threshold: pure black and white).
- **Pictures:** the 73 scenes whose page lies whole in the frame, straightened with the
  true outline (so detection does not matter here), full size. Real OCR engine of the app,
  release build, emulator `Claude_Code_Test`. Raw lines: `docs/image_spike_data/enhance_run1_73pages.log`.
  Before/after strips (one picture per option, in the order above, magenta lines between
  them): `docs/image_spike_data/enhance_examples/`.

### Results (mean over pages; "worse/better" = word recall more than 2 points below/above `color`)

| option | CER all (73) | recall all | CER hard (23) | recall hard | worse / better (all) | extra time on the emulator |
|---|---|---|---|---|---|---|
| color | 0.0081 | 0.974 | 0.0029 | 0.984 | - | 0 |
| gray | 0.0075 | 0.977 | 0.0019 | 0.989 | 6 / 12 | 11 ms |
| flat | 0.0079 | 0.975 | 0.0029 | 0.986 | 5 / 7 | 86 ms |
| clahe | 0.0073 | 0.976 | 0.0029 | 0.983 | 8 / 9 | 90 ms |
| flat+clahe | 0.0073 | 0.974 | 0.0029 | 0.982 | 4 / 7 | 168 ms |
| binary | **0.0131** | **0.964** | 0.0039 | 0.986 | **15** / 6 | 119 ms |

"Hard" = the categories `light`, `low_contrast`, `combined`, `crumple`. The per-category
tables are in `docs/image_spike_data/enhance_aggregate.py` run on the log.

1. **No option is clearly better than the picture as it is.** All differences between
   `color`, `gray`, `flat`, `clahe` and `flat+clahe` are below one point of CER and word
   recall, with as many pages better as worse: this is OCR noise, not a gain. The engine
   already reads these synthetic pages (mild shadows, contrast down to 0.42) almost
   perfectly.
2. **Binarisation hurts.** The worst CER, 15 pages worse, one small page lost 19 points of
   word recall. It also throws away colour and grey levels the PDF should keep.
3. **Visually, `flat` is the only option that clearly helps a reader**: it removes the
   shadow band and the light gradient and keeps the paper's colour (strip 3 of
   `combined_71.jpg`). `clahe` raises the noise and the shadow edge with it. `binary`
   looks clean but is lossy.
4. **The OCR time column of the logs is not an effect of the options.** `color` is always the
   first read of a page and is about 0.4 s slower than the others (first read of a new file);
   this was not separated further and no speed is claimed from it.
5. **Not measured:** real photos (blur, glare, real shadow of a hand or phone). The generator's
   shadows are mild and smooth. If a real receipt in the phone check shows that shadow hurts
   the reading, `flat` is the candidate (about 90 ms for a 1.4 MP page, pure Dart, no
   OpenCV needed).

### Suggested default

**No enhancement for the OCR and none in the PDF** (the page keeps colour and every grey
level, the PDF loses no information). Keep `flat` as a prepared option, behind a switch,
for a real-photo test; do not use `binary` and `clahe`. This is a suggestion from synthetic
data only; the phone check (`docs/PHASE_6_0_VALIDATION.md`) shows the original and the
`flat` result side by side so that you can judge on real pages.

## 6. Processing in the background while shooting (request 5)

### 6.1 What the app already does (read in `lib/`, nothing changed)

The reading **already runs behind the camera**: `OcrSession` (`recognize_pages.dart`)
takes every shot (`add(key, path)`), prepares it (`PrepareImageForOcr`, in a Dart isolate
or natively) and reads it (the OCR worker isolate), one page at a time, while the user
keeps shooting. `remove(key)` (the undo arrow) cancels that page and deletes its working
copy, `cancel()` and `stopReading()` serve the Cancel button and Back (ADR-028).
**The PDF is made from the same working copy** that the OCR reads (`UprightImage`,
longest side 2560, JPEG 95), and the originals in `./pictures` and the Gallery are
written separately at "Done" (ADR-026) and are not touched by any of this.

So "background processing" is not a new mechanism. The question is only where the crop goes.

### 6.2 Where the crop goes (proposal, to be confirmed in Phase 6.1)

Between "prepare" and "read", as one more step of the same per-page queue:

```
shot -> PrepareImageForOcr (upright, <= 2560)
     -> PageStraightener (new port in domain/ports; implementation in services/image,
        in an isolate like DartUprightImageMaker): detect on a downscaled grey copy,
        confidence >= 0.5 and enclosing quad -> warp -> write a NEW working copy
        (otherwise the working copy stays the whole frame)
     -> OCR on that working copy -> the PDF takes the same working copy
```

- **Undo and Back:** `OcrCancellation` is checked between the steps (before detection, before
  the warp, before the write); the new working copy is `e.image` of the same entry, so
  `_discard` deletes it as it deletes today's. Nothing outside the cache is created.
- **`ScanAndSend` and ADR-028:** no change in the flow. `_makePdf` already reads
  `page.image`; it would just be the crop. The stages, the Cancel button and the
  texts stay as they are. Only a stage name for the log ("straightening") may be added.
- **The originals** are untouched (decision 2 of the request); the crop exists only as a
  working copy in the cache and in the PDF.
- **Dependency rule:** the port in `domain/`, the OpenCV or Dart code in `services/`;
  `domain/` stays free of plugins.

### 6.3 Measured on the emulator (same code as the phone screen, `bg_eval_main.dart`)

21 and 5 pages of the synthetic set, each prepared in an isolate and read by the real
OCR one after the other. "Today" = prepare + OCR of the whole frame; "new" = prepare +
detection + warp + OCR of the crop (A3, pure Dart; one row with A1). Wait = time from
the last shot to the end of all the work. Debug-free release build, x86_64 emulator,
2 GB, first row of each pair is today. Raw lines: `docs/image_spike_data/background_run1_emulator.log`.

| pages | shots every | today: wait after the last shot | new (A3) | prepare per page (today / new) | OCR per page (today / new) |
|---|---|---|---|---|---|
| 5 | all at once | 13.1 s | **10.4 s** | 507 / 546 ms | 1425 / 1007 ms |
| 21 | all at once | 41.8 s | **37.2 s** (A1: 36.2 s) | 406 / 455 ms | 1256 / 937 ms |
| 5 | 2.5 s | 3.0 s | 3.6 s | 511 / 647 ms | 1292 / 1417 ms |
| 21 | 2.5 s | 1.9 s | 2.1 s | 421 / 434 ms | 1162 / 1025 ms |

1. **With shots at a human pace (2.5 s) the work keeps up in both cases**: after the last
   shot the user waits 2 to 4 s, and the crop does not change that in any way that the
   numbers can tell apart (one page of difference in noise). The 27 s of Phase 5.1 came
   from taking the shots back to back, faster than the reading can follow.
2. **When the pages arrive at once, the crop is about 11% faster overall** (13.1 -> 10.4 s;
   41.8 -> 37.2 s): the OCR of the crop is about 25% faster, and the detection and the warp
   take back a part of it. That is less than the 6 to 8 s that section 4.1 estimated for 21
   pages; the measured saving is **4.6 s**.
3. **A cheap speed-up that does not depend on the crop (not built, not measured as a
   change):** the preparation (about 0.4 to 0.5 s per page) runs before each reading,
   not during the previous one. Preparing page k+1 while page k is being read would hide
   it: for 21 pages at once up to about 8 s less, in the same order as the crop's gain.
4. **Memory:** peak 605 MB at 21 pages (547 MB today).
5. **Not measured here:** the effect on the live camera preview (an emulator has no real
   camera and its 4 cores are shared). `background_page.dart` in the spike APK counts the
   slow frames of its own screen while the same work runs (a moving bar): the phone check
   reads the numbers. The work runs in isolates, so the interface thread is free in
   principle; the phone is what tells whether the CPU load shows.

## 7. Autofocus before the shutter (request 7; report only, the camera is not changed)

What the code does (read, `lib/services/camera/plugin_camera_service.dart`; the plugin is
`camera` 0.12.1 with `camera_android_camerax` 0.7.5+1):

- The app opens the back camera at `ResolutionPreset.max`, JPEG, sets the flash off and
  **never sets a focus mode, a focus point or an exposure mode**. It calls `takePicture()`
  as soon as the shot is requested and does **not** wait for any "focused" signal.
- The plugin starts in `FocusMode.auto` (`android_camera_camerax.dart`, `_currentFocusMode`).
  That is CameraX's default automatic focus; tap-to-focus (`setFocusPoint`) and locking
  (`setFocusMode(locked)`) exist in the plugin and are not used.
- **Not verified:** what CameraX itself does between `takePicture()` and the exposure
  (whether a still capture waits for the focus to settle). That is inside the library and
  cannot be seen from the app code; an emulator with a virtual scene does not focus. It has
  to be judged on the phone: shoot at once after moving the phone closer and again after
  one second, and compare the sharpness (a line of the validation table).
- The blur of the real receipt in Phase 2 can therefore be caused by (a) the shutter before
  the focus had settled, (b) hand movement, (c) low light with a long exposure. This
  report cannot tell which. A small, safe change for Phase 6 would be a short wait or a
  focus check before the shot, and it must be tried on the phone.

## 8. Size of OpenCV in the APK and the licences of its codecs

**Measured** (release, arm64, `flutter build apk --release --target-platform android-arm64`):

| | bytes |
|---|---|
| empty Flutter app (`flutter create --empty`, same Flutter, release arm64 APK) | 15,043,420 (14.3 MiB) |
| `libdartcv.so` (OpenCV with `imgcodecs` and `imgproc` only, the package default) in the spike APK, arm64 | 10,496,648 (10.0 MiB), stored uncompressed |
| `libonnxruntime.so` in the same APK, arm64 (already in the main app, for the OCR) | 28,637,280 |

- **The cost of choosing A1 (OpenCV) is about 10.5 MB per ABI in the APK** (about +70% on an
  empty app; the main app's own size is not part of this measurement). **A3 (pure Dart) costs
  no native library**, only some Dart code. The 26,043,372 B of section 1 was an earlier
  build of other contents; this table replaces it.
- The spike APK itself is 210 MB because it carries the OCR models, the two sets of test
  pictures and the three ABIs of the ONNX Runtime plugin (`flutter_onnxruntime` ships
  `armeabi-v7a` and `x86_64` libraries whatever `--target-platform` says). It is a test
  tool, not a size reference.
- OpenCV is built from source by the build hook of `dartcv4` 2.2.2 (release build 312 s on
  this PC, section 1), which also makes every CI build slower.
- **Codecs inside that build** (from `dartcv4/src/cmake/opencv_options.cmake`): JPEG, PNG,
  WebP, TIFF, OpenJPEG (JPEG 2000), zlib, protobuf and QUIRC, plus OpenCV's own HDR, Sun
  Raster, PXM and PFM readers. FFmpeg, OpenEXR and IPP are off. The licences of those
  libraries, **from what is known of each upstream project and not re-read in the sources
  here** (the OpenCV source tree is downloaded only while building): libjpeg-turbo
  (BSD-3 and IJG, zlib), libpng (libpng licence), libwebp (BSD-3), libtiff (BSD-like),
  OpenJPEG (BSD-2), zlib (zlib), protobuf (BSD-3), QUIRC (ISC); OpenCV and `opencv_dart`
  Apache-2.0. All are permissive. If A1 is chosen, the notices belong in
  `THIRD_PARTY_NOTICES.md`, and the codec list should be read from the sources of the
  exact version before release.

## 9. Overall reading and recommendation

- **What the crop gives:** a clear gain for small pages in a big picture, a 25% faster OCR on
  the crop, and 11% less total time when pages come at once. On clean pages the accuracy
  does not change. It never lost content with the enclosing outline and the 0.5 confidence.
- **What it costs:** 18% of the pages fall back to the whole frame (correctly in 6 of 14
  cases); detection and warp take 0.1 to 0.15 s per page; A1 costs about 10.5 MB of APK.
- **A3 or A1:** both give the same crops (0 cuts, 18.2% fallback). A1 is 3 to 4 times
  faster in the detection (21 against 65 ms, 28 against 79 ms at full size), A3 costs no APK
  and no native build. With the numbers of section 6 the speed difference is below the
  noise of one page, so **A3 is enough for the first version**; A1 stays an option if the phone
  check shows A3 is too slow on a real 12 MP page.
- **Small pages (A3small, the lowered area bound):** the crop helps the 5 small pages (CER
  0.185 -> 0.071 with the perfect crop) but 2 of the 4 empty scenes also get a confident
  crop. No content is lost, only the PDF page would be a meaningless crop. Included
  as an option in the phone check (a line of the table), **left out of the default** until
  real small receipts show that they are worth that risk.
- **Safety check:** not by double OCR (section 4.4). The enclosing outline and the
  confidence are the protection; a check on the crop alone is a candidate.
- **Contrast and shadow:** no option beats the picture as it is on synthetic pages;
  `flat` is prepared, `binary` and `clahe` are rejected (section 5).
- **Background:** the app already reads behind the camera; the crop fits as one more step of
  the same queue (section 6.2). The real gain to look for is pipelining the preparation.
- **Autofocus:** the app waits for nothing before the shutter (section 7); to be judged on
  the phone.

## Appendix. Results on the phone (user), 2026-11

**These are human tests on the user's own phone with the spike APK, not automated measurements.** Nothing of the
documents was sent to Claude; only the answers below.

### Controlled checks, method A3 (pure Dart)

Nine situations (well lit, badly lit, crumpled receipt, tilted, dark background, document out of the frame, small
receipt, table with no document, the hard receipt of Phase 2): **all satisfactory**. In random checks no content was
lost. With bad light and with a dark background the app often falls back to the whole frame (safe, by design).

### Background test on the phone (today / new with the crop)

| Pages | Shots every | Wait after the last shot (s) | Frames above 33 ms |
|---|---|---|---|
| 5 | 2.5 s | 5.2 / 4.9 | 7 / 1 |
| 21 | 2.5 s | 8 / 7.7 | 1 / 3 |
| 21 | all at once | 56.4 / 65.4 | 0 / 3 |

The bar did not stick. So the reading in the background does not disturb the camera, and **the crop alone gains no
time when the pages come at once** (65.4 against 56.4 s on the phone; on the emulator it was 37.2 against 41.8 s).
The aim of Phase 6.1 is therefore to hide the preparation between the shots (pipelining), not to speed up the
all-at-once case.

### Conclusions of the user

- **A1 (OpenCV) is out:** on real documents it gave the worst results, wrong crops, and it distorted a page that was
  already straight because of a diagonal line in the content. Only A3 goes on.
- **Focus:** the blur of a photo taken close to the text is the behaviour of the lens and the automatic focus of the
  phone, the same as in the phone's own camera app. The camera of the app is not changed.
- **Light:** in bad light or on a dark background the crop is not applied (whole frame). Section "Phase 6.2" of
  `ROADMAP.md` records a proposal for that (a milder light normalisation for the detection only).


## Phase 6.2: the light metric on the synthetic scenes

Tool: `dart run tool/light_metric_eval.dart` (invented receipts only; the scenes of the unit tests, tilted, light scaled down like a lower exposure, metric from a 160 px copy as the after-shot check does). Threshold: paper level below **40** is "low light" (ADR-030).

The model is **linear** (a phone raises its exposure in the dark, so real numbers differ): the table says how the metric behaves, and the threshold is calibrated on the phone with the diagnostics screen (`PHASE_6_2_VALIDATION.md`).

| scene | light | paper | contrast | low light |
|---|---|---|---|---|
| receipt on a table | 100% | 98.8 | 89.4 | no |
| receipt on a table | 70% | 69.4 | 62.7 | no |
| receipt on a table | 50% | 49.4 | 44.7 | no |
| receipt on a table | 40% | 39.6 | 36.1 | YES |
| receipt on a table | 30% | 29.8 | 27.1 | YES |
| receipt on a table | 20% | 19.6 | 18.0 | YES |
| receipt on a table | 12% | 11.8 | 11.0 | YES |
| receipt on a dark background | 100% | 98.8 | 89.4 | no |
| receipt on a dark background | 70% | 69.4 | 62.7 | no |
| receipt on a dark background | 50% | 49.4 | 44.7 | no |
| receipt on a dark background | 40% | 39.6 | 36.1 | YES |
| receipt on a dark background | 30% | 29.8 | 27.1 | YES |
| receipt on a dark background | 20% | 19.6 | 18.0 | YES |
| receipt on a dark background | 12% | 11.8 | 11.0 | YES |
| faint thermal receipt on a table | 100% | 72.2 | 24.3 | no |
| faint thermal receipt on a table | 70% | 50.6 | 16.9 | no |
| faint thermal receipt on a table | 50% | 36.1 | 12.2 | YES |
| faint thermal receipt on a table | 40% | 28.6 | 9.8 | YES |
| faint thermal receipt on a table | 30% | 21.6 | 7.5 | YES |
| faint thermal receipt on a table | 20% | 14.1 | 4.7 | YES |
| faint thermal receipt on a table | 12% | 8.6 | 3.1 | YES |

Reading: the paper level follows the light almost one to one (a page and a dark background give the same numbers because the percentile is the paper, not the background), the contrast follows it too, and the faint thermal scene has a lower paper level at full light (72) and a contrast of only 24, so such a receipt crosses 40 earlier (at about 50% of the light). The contrast is not used for the warning.

**Item E of the request (detection of the page on a picture with a mild light flattening):** not measured in this phase, no claim and nothing built.
