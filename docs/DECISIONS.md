# Decisions

## ADR-001 Privacy first, fully local
No developer cloud, mandatory app account, subscription or bank API. Internet
is allowed only for services, optionally, and without sending personal data.
E-mail delivery is started by the user and goes from the user's own account to
the user's chosen recipient; the app itself runs no backend.

## ADR-002 Business logic in Rust (Budget)
Parsing, rule engine and statistics live in Rust in the Budget app. For Scan:
not in Phase 0; candidate in the image processing phase (see ARCHITECTURE §10).

## ADR-003 Independent apps
Scan does not depend on Budget and Budget does not depend on Scan. Only the JSON
contract links them. Scan works standalone (plain documents, mail delivery).

## ADR-004 State management, DI, routing
flutter_bloc (Cubit), get_it (manual registration, new container per build),
go_router. Chosen for testability. Not required to match Budget.

## ADR-005 User-chosen storage folder
The user picks a visible folder at first launch (Android SAF tree URI with
persisted permission). Inside it (`./` below) Scan writes two sub-folders, so
the user can share files to other apps or to their own cloud storage:

- `./pictures/` holds the original JPEGs. They are always saved, so they can be
  shared with tools that do not accept PDF.
- `./pdf/` holds the PDFs.

Naming: both outputs of a scan share one stem, the device time as
`YYYY-MM-DD_HH-MM-SS` (the same text as the e-mail subject). PDF:
`pdf/<stem>.pdf`. Images: `pictures/<stem>_<n>.jpg`, `n` starting at 1. If the
stem already exists (two scans in the same second) it gets a suffix `-2`, `-3`,
and so on, so the PDF and the images of one scan always match by name.

Gallery copies are optional and off by default, with an explanation of what
sharing to the Gallery implies. The switch only adds one extra copy in the
Gallery; it does not change where the originals are stored. The e-mail contains
only the PDF.

## ADR-008 Scan without JSON
Scan does not generate JSON. The Budget app reads the PDFs directly. The
JSON contract (`DATA_CONTRACT_V1.md`) is kept as history only and is marked
superseded: `schemaVersion`, `documentId` and `documentType` are cancelled. The
Receipt/Document choice and the soft filter existed for the JSON export and are
suspended (open, decided in the OCR phase). Open question, decided in the PDF
phase: either the Scan PDF has an invisible text layer (searchable PDF) or
Budget does its own OCR. ADR-003 is unchanged: the apps stay independent.

## ADR-006 Sending model
Direct sending from the app (one click) with a configurable sending account that
may differ from the device account. Provider abstraction (`MailProvider`) with
Gmail, Outlook and Yahoo. Authentication approach decided at the start of the
mail phase. If OCR yields no text, the mail is still sent with the PDF and the
user is notified.

## ADR-007 Hand-written localization
EL/EN strings are an abstract class with two implementations, so a missing
translation is a compile error. Can move to ARB later.

## ADR-009 Names of the Gallery copies, app icon, splash
The optional Gallery copy is named `scan_YYYY-MM-DD_NN.jpg`:

- Prefix `scan_` makes the copies easy to filter in the Gallery. The date is
  the device date, without the time.
- `NN` is a **daily counter**, two digits with a leading zero (`01`, `02`...)
  and no limit at 99 (`100`, `101`...). Every image copied to the Gallery takes
  the next number of the day, so a multi-page scan uses consecutive numbers.
  A new device date starts again at 1.
- The counter advances only after a copy was saved, so failures leave no gap,
  and with the Gallery switch off no number is used. The date and the last
  number live in the key/value store (`gallery.counter.date`,
  `gallery.counter.last`).
- The files in `./pictures/` keep their own names (`<stem>_<n>.jpg`, ADR-005).
- Technically: `gal` names the copy after the file it is given, so the picture
  is first copied under the wanted name into the app cache
  (`gallery_copies/`), handed to `gal` and deleted again; leftovers are purged
  at start-up. The counter is a port (`GalleryCounterStore`), the naming a pure
  class (`GalleryNaming`, injected clock).
- Known limit: if the app data is cleared the counter restarts at 1 while
  older `scan_<date>_01.jpg` copies may still exist; Android then adds its own
  suffix to the new file name instead of overwriting.

App icon and splash are generated from two source images in `assets/branding/`
by `tool/generate_branding.dart` (dev dependency `image`, pure Dart), and the
generated files are committed:

- Adaptive icon: the symbol is keyed out of the green image (spill
  `G - max(R, B)`: background from 110, symbol up to 30, linear between; green
  removed from soft edges), scaled so the smallest circle around its opaque
  pixels fits the 66dp safe zone of the 108dp canvas, on a radial-gradient
  background drawn as a vector (no image) with the colours of the original
  plate. Legacy icon (Android 7.x): the original image.
- Splash: the original icon, scaled so the whole plate sits inside the 192dp
  circle that Android 12+ masks the icon with, on the colour of the frame
  around the plate (same in light and dark mode). Before Android 12 the same
  image is centred by `launch_background`. No splash package is used.
- Out of scope: monochrome (themed) icon.


## ADR-010 OCR engine: Paddle only, behind `OcrEngine`
Scan reads text with PaddleOCR PP-OCRv5 (detection + recognition, ONNX
Runtime through `flutter_onnxruntime`). No ML Kit (no Greek, and it crashed
under R8 in the spike) and no Tesseract (does not build with the current Gradle
template, and it ignores the EXIF orientation). The domain only knows the port
`OcrEngine` (`domain/ports/ocr_engine.dart`), so the engine can be replaced
without touching the use cases or the UI.

The run configuration comes from the phone measurements of Phase 1.6 to 1.6c
and lives in one place, `OcrConfig` (no magic numbers elsewhere):

- provider CPU, recognition batch 1 (batch 4 or 8 was 40% to 70% slower on the
  phone), detection side 960 (peak memory about 616 MB; 1280 gave about
  1031 MB), 4 threads (the spike default; the thread grid on the phone is not
  finished);
- the stock recognition model, not the ArgMax derivative: it was about 6%
  slower on the phone and saved only about 250 ms of CTC decoding, which typed
  loops in Dart do in about 70 ms. Models stay exactly as their source
  publishes them (one hash each);
- XNNPACK and NNAPI are not used: they did not beat the noise on the phone and
  the accuracy check on the phone was never made;
- the engine lives in one long-lived background isolate with the models loaded
  once. On the phone this does not make the reading faster, but it keeps the UI
  isolate free (a stall of about 20 ms against 125 to 150 ms);
- the page timeout is 45 s and the result is a sealed type (`success`,
  `timedOut`, `failed(reason)`, `cancelled`), never an exception to the UI.

## ADR-011 Language packs per script, chosen by the user
A pack is one recognition model with its dictionary; the detector is shared.
Two packs are bundled: `greek` (Greek and English, about 7.8 MB) and `latin`
(English and the Latin-script languages with accents, about 7.9 MB). The
choice is explicit and visible in Settings; the app never detects the language,
because a wrong pack fails badly (mixed Greek and English: Greek pack CER 2.9%,
Latin pack 26%; accented lines: Greek pack 0 of 284 accented letters, Latin pack
284 of 284; see `OCR_LANGUAGE_PACKS.md`).

First run: `greek` when the device language is Greek, `latin` otherwise. The
choice is stored in the key/value store (`settings.ocr.pack`); the first-run
wizard is unchanged. The registry (`OcrLanguagePackRegistry`) describes packs
with an availability (`bundled` or `downloadable`) so that packs outside the APK
(ru and others) fit later; downloading is future work and there is no network
code in the OCR layer. Packs not in the APK must be fetched from our own hosting
with a pinned SHA-256 (see the open item in `THIRD_PARTY_NOTICES.md`).

## ADR-012 The OCR sits on the SCAN & SEND path
The PDF of Phase 3 is meant to be searchable (an invisible text layer), so the
text and its geometry are needed while the document is made, not afterwards.
That is why the OCR result carries four corner points per line, normalised to
the upright working image, and why the reading of each page starts as soon as
the page is shot (Multi Page: the next page is photographed while the previous
one is read). Per-character boxes (`charBoxes`) stay empty in Phase 2: Phase
1.7 decides, on the phone, whether the selection and copying of a code such as
an RF code needs them. The text screen of Phase 2 is a check tool, not the final
UX (the final flow is one click with no text screen).

## ADR-013 The scanner never changes the text it reads
No correction of look-alike letters (Greek and Latin), no spell checking, no
normalisation. The only thing allowed is to flag lines of low confidence
(handwriting that comes out as rubbish): below `OcrConfig.minLineConfidence` the
line is marked `filtered`. The result keeps every raw line and the flag; only
the visible text leaves the flagged lines out. The threshold is 0.5, the
`drop_score` default of PaddleOCR itself; the spike recorded only mean
confidences, so there is no tuned figure of our own (Phase 2 measurements are in
`PHASE_2_VALIDATION.md`). Any matching that must tolerate look-alike letters
belongs to the consumer (Budget normalises text already).

## ADR-014 Image decode policy
- Never decode on the UI isolate. The 200 MP photo of Phase 1.6c froze the UI
  for about 8 s per Dart decode and ended in the "not responding" dialog.
- The header is read first (JPEG SOF or PNG IHDR, a few small reads) and gives
  the size without decoding anything.
- Up to 8 MP: `package:image` in a background isolate. Above 8 MP and up to
  50 MP: native decode in Kotlin (`ImageDecodeHandler`), with `inSampleSize`
  so the full-size bitmap is never created, then rotation and scaling in one
  pass. Above 50 MP: refused with `imageTooLarge` (the reading fails, the scan is
  still saved); the limit is inclusive at both ends.
- The result is the upright working copy: EXIF orientation applied (the invalid
  value 0, and anything outside 1 to 8, mean no rotation), long side at most
  2560, JPEG quality 95, in the app cache (`ocr_work/`, purged at start-up).
  The PDF of Phase 3 will use the same file.
- Sizes are the pixels of the decoded image and the header's SOF size, never
  `ExifImageWidth/Height` (false on Xiaomi camera files: 1840x4080 for a
  972x1260 file).
- One image at a time, buffers released after each page, models released when
  the result screen is left.
