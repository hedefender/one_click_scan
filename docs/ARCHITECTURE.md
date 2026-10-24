# Architecture (Phase 2)

Status: Phase 0 skeleton and Phase 0.5 settings screen are committed; Phase 1
adds the camera and saving the originals (see `PHASE_1_VALIDATION.md`);
Phase 1.1 fixes found in the manual check (see `PHASE_1_1_VALIDATION.md`);
Phase 1.2 adds the app icon, the splash screen and the Gallery copy names
(see `PHASE_1_2_VALIDATION.md`, ADR-009); Phase 2 adds the OCR layer
(section 8d, ADR-010 to ADR-014, `PHASE_2_VALIDATION.md`).

## 1. Principles

- Privacy first, fully local (ADR-001). No developer cloud, no mandatory app
  account, no analytics. Logs never contain user content.
- Independent from the Budget app (ADR-003). Scan produces no JSON (ADR-008):
  Budget reads the PDFs directly. `DATA_CONTRACT_V1.md` is superseded.
- Maintainability and testability over feature completeness.
- Every phase leaves a runnable app.
- Android first, iOS later: platform code is isolated behind interfaces in
  `services/`.

## 2. Folder layout

The layout follows the scheme in the project instructions. How each folder is
interpreted:

```
lib/
├── main.dart            entry point, wires real platform adapters
├── app/                 composition root: DI container, router, root widget
├── core/                framework-light basics: config, errors, logging, route paths
├── shared/              small reusable helpers (validators, later formatters)
├── domain/              entities, repository interfaces, ports, use cases.
│                        Pure Dart. `ports/` holds the interfaces of services
│                        that use cases need (implemented in `services/`).
├── data/                repository implementations, data sources (key/value store)
├── services/            platform/IO integrations behind interfaces
│                        (Phase 0: storage folder picker; later: camera, OCR,
│                        PDF, mail, image processing)
├── presentation/        app-wide UI infrastructure: theme, localization,
│                        app-wide state (SettingsCubit)
└── features/<name>/     feature modules: pages, cubits, keys, and a
                         <name>_module.dart that registers the feature's DI
                         and exposes its routes
```

`domain/` and `data/` are global (shared by all features). Features own only
their presentation and wiring. This is the interpretation of the original
scheme (`data/`, `domain/`, `presentation/` next to `features/`); if you want
per-feature layers instead, it is a mechanical move.

## 3. Dependency rule

```
features ──► presentation ──► domain ◄── data
   │                            ▲          │
   └──────► services ───────────┘          │
app (composition root) ──► everything      │
core, shared ◄── used by all, depend on nothing of ours
```

- `domain/` imports only Dart and `equatable`. No Flutter, no plugins.
- `data/` implements `domain/` interfaces; plugin details (shared_preferences)
  are confined to one adapter class.
- `services/` expose interfaces; the Android implementation talks to native
  code over a MethodChannel.
- `domain/` never imports `services/`. Interfaces that a use case needs are
  ports in `domain/ports/` (`ScanFileStore`, `GalleryService`,
  `GalleryCounterStore`);
  their implementations stay in `services/` and point inwards.
- Features never import other features.

## 4. State management, DI, routing

- State: `flutter_bloc` (Cubit). Chosen as the most testable option and the
  most conventional fit for Clean Architecture. The Budget app is independent,
  so it is free to differ.
- DI: `get_it`, registered manually in `app/injection.dart`. A fresh
  container is built per call (`GetIt.asNewInstance()`), no global singleton,
  so tests are isolated and can inject fakes for platform adapters.
- Routing: `go_router`. Each feature module exposes its routes; `app/router.dart`
  composes them. The initial route comes from `firstRunCompleted`.

## 5. Settings storage

- Interface `KeyValueStore` (synchronous reads) in `data/datasources/`.
  Production adapter: `SharedPreferencesKeyValueStore`. Tests: in-memory fake.
- `SettingsLocalDataSource` maps `AppSettings` to flat keys, stores a
  `settings.schemaVersion`, and reads defensively (unknown values fall back to
  defaults, so a corrupted store cannot crash startup).
- `SettingsRepository` exposes `load`, `save` and a `changes` stream.
  `SettingsCubit` mirrors the stream, so language changes apply instantly.
- Writers use the `UpdateSettings` use case (read-modify-write).

## 6. Settings model (Phase 0)

| Field | Meaning |
|---|---|
| `language` | `el` or `en`. Defaults to the device language (Greek or English). |
| `firstRunCompleted` | Set when the wizard finishes. Drives the initial route. |
| `storageFolder` | User-chosen visible folder (Android: persisted SAF tree URI + display name). Mandatory. |
| `mailProvider` | Gmail, Outlook or Yahoo. Only stored in Phase 0. |
| `senderAccount` | Account the app sends from. May differ from the device account so the user's main Sent folder does not fill up. |
| `destinationMode` / `customDestination` | Send to the sender's own address, or to another address. |
| `saveToGallery` | Copy originals to the Gallery. Off by default; the wizard explains what sharing to the Gallery means. |
| `ocrPackId` | OCR language pack (`greek` or `latin`), chosen in Settings (Phase 2). Default `greek` for a Greek device, `latin` otherwise; the wizard does not ask. |

No passwords or tokens are stored in Phase 0. Credentials/OAuth tokens arrive
with the e-mail phase and will use the platform secure storage, not
`shared_preferences`.

## 7. First run wizard

Four steps: welcome + language, storage folder (mandatory, explained),
mail (provider, sending account, recipient), Gallery copies (explained).
Answers are persisted per step, so an interrupted wizard resumes with
earlier answers prefilled; `firstRunCompleted` is set only on Finish.

## 7b. Settings screen (Phase 0.5)

Feature `features/settings/`, route `/settings`, opened from the home app
bar. `SettingsEditorCubit` owns the unsaved e-mail draft; language, folder and
the Gallery switch are saved at once through `UpdateSettings`. The app-wide
`SettingsCubit` is unchanged and keeps mirroring the stored settings. The
e-mail rules live in `domain/validation/mail_settings_validation.dart` and are
shared with the wizard (`FirstRunState`). Leaving with unsaved e-mail changes
asks for confirmation. The theme always follows the device (no option).

`HomeCubit` checks `StorageFolderPicker.hasAccess` when home opens, when the
app resumes and when returning from settings; if access is lost, home shows a
banner that leads to settings. The domain rule "imports only Dart and
`equatable`" is read as packages: `domain/validation` may use the pure-Dart
`shared/validators`.

## 8. Storage folder (SAF)

`StorageFolderPicker` is the interface. On Android, `MainActivity.kt`
(`android_overlay/`) launches `ACTION_OPEN_DOCUMENT_TREE`, takes persistable
read/write permission and returns `{uri, name}`. `hasAccess` checks that the
permission is still granted (it can be revoked by the user or the system);
later phases use it before every write and re-prompt when missing.

Inside the chosen folder (`./`) later phases write `./pictures/` (original
JPEGs, always saved) and `./pdf/` (PDFs). Both outputs of one scan share a
stem, the device time `YYYY-MM-DD_HH-MM-SS` (same as the e-mail subject, with a
`-2`, `-3` suffix on collision): `pdf/<stem>.pdf`, `pictures/<stem>_<n>.jpg`
with `n` from 1. The Gallery switch only adds one more copy there; it does not
move the originals. The e-mail contains only the PDF (ADR-005).

## 8b. Camera and saving the originals (Phase 1)

Feature `features/scan/`, routes `/scan` and `/scan/result`.

- `ScanCubit` is the state machine: check folder access, open the camera,
  take one (Single) or many (Multi) pages, then store them. Shots are written
  to the app cache first (`scan_pages/`); only Done (or the Single shot)
  copies them into `./pictures`. Leaving, cancelling or closing the cubit
  deletes unsaved shots; at start-up `main.dart` purges leftovers of a killed
  scan. The cache files of a saved scan are deleted when the result screen is
  left.
- `CameraService` (`services/camera/`): `PluginCameraService` uses the
  `camera` package, which on Android is the endorsed CameraX implementation
  (`camera_android_camerax`). The plugin types stay in that one file. The
  camera is released when the app is paused and reopened on resume.
- `ScanFileStore` (port in `domain/ports/`, implementation in
  `services/scan_files/`): Android implementation over the
  MethodChannel `com.example.one_click_scan/scan_files`
  (`ScanFilesHandler.kt`). Bytes never cross the channel: the copy runs
  natively, from the cache file to the SAF folder, on a background thread.
  `StoreScanPages` is all or nothing: if a file fails, the ones already
  written are deleted and the pages stay in the cache for a retry.
- The `./pictures` folder holds a `.nomedia` marker (created
  before the first copy, idempotent, a failure is only logged). It keeps the
  system media index (Gallery, Google Photos) away from the originals, so the
  Gallery switch alone decides whether a copy appears there. The marker stays
  whatever the switch says.
- `GalleryService` (port in `domain/ports/`): `gal` package, which saves the
  copy under `Pictures/` (no album) and names it after the file it is given.
  The permission is asked only when a copy is requested; a failing copy is
  reported per picture and never fails the scan.
- Gallery names (Phase 1.2, ADR-009): `GalleryNaming` (pure, injected clock)
  builds `scan_YYYY-MM-DD_NN.jpg`; `GalleryCounterStore` (port) keeps the daily
  number, `KeyValueGalleryCounterStore` (in `data/`) implements it over the
  key/value store. `StoreScanPages` asks for the next number per picture and
  records it only after the copy succeeded. `GalGalleryService` copies the
  picture under the wanted name into the cache folder `gallery_copies/`, gives
  that file to `gal` and deletes it; `IoScanTempStore.purgeAll` also empties
  that folder at start-up.
- Naming (`ScanNaming`, pure, injected clock): see ADR-005.
- `MainActivity.kt` only registers the two new handlers
  (`ScanFilesHandler`, `SystemHandler` for "open app settings").
- Screen layout (Phase 1.1): like a camera app, the preview fills the screen
  (contain, no crop) and all controls float above it. Portrait: Single/Multi
  in the app bar, thumbnails and buttons along the bottom. Landscape (width >
  height): buttons and a vertical thumbnail strip on the right. The preview
  rotation itself is the camera plugin's: it follows the device sensor.
- Orientation: the camera writes the rotation as an EXIF tag (orientation 6 on
  the emulator), the pixels are not rotated. Baking the rotation into the
  pixels is left to the phases that decode the image anyway.

## 8c. App icon and splash (Phase 1.2)

Generated by `tool/generate_branding.dart` from `assets/branding/`
(`icon_original.jfif`, `icon_foreground_green.jfif`); the generated resources
are committed under `android/app/src/main/res/`. `dart run
tool/generate_branding.dart` rebuilds them (needs the dev dependency `image`).
Details and numbers: ADR-009. `test/branding/branding_assets_test.dart` reads
the generated PNGs and checks alpha, transparent corners and the safe zone.

- Adaptive icon (Android 8+): `mipmap-anydpi-v26/ic_launcher.xml`, background
  `drawable/ic_launcher_background.xml` (radial gradient), foreground
  `drawable-*dpi/ic_launcher_foreground.png`. Legacy icon:
  `mipmap-*dpi/ic_launcher.png`. The manifest is unchanged
  (`@mipmap/ic_launcher`).
- Splash: `drawable-*dpi/splash_icon.png`, colour `@color/splash_background`
  (`values/colors.xml`). Android 12+: `values-v31` and `values-night-v31`
  (`windowSplashScreenBackground`, `windowSplashScreenAnimatedIcon`). Before
  Android 12: `drawable/launch_background.xml` centres the same image.

## 8d. OCR (Phase 2)

Decisions: ADR-010 to ADR-014. Numbers behind them: `OCR_SPIKE_RESULTS.md`
sections 9 to 11 and `OCR_LANGUAGE_PACKS.md`. The OCR code is new; nothing was
imported from `spikes/ocr_spike/` (it stays as the reference).

### Layers

```
domain/
  entities/   OcrLine (text, confidence, quad of 4 points 0..1, row, filtered,
              charBoxes = null), OcrResult, OcrOutcome (sealed: OcrSuccess,
              OcrTimedOut, OcrFailed(reason), OcrCancelled), OcrProgress,
              UprightImage
  ocr/        OcrConfig (every tunable), OcrLanguagePack(+Registry),
              planImageDecode (8 and 50 MP), applyConfidenceFilter,
              OcrCancellation
  ports/      OcrEngine, ImageHeaderReader, UprightImageMaker, OcrWorkStore
  usecases/   PrepareImageForOcr, RecognizePages (+ OcrSession)
services/
  image/      header and EXIF parser (pure), DartUprightImageMaker (isolate),
              NativeUprightImageMaker (MethodChannel .../image_decode),
              IoOcrWorkStore
  ocr/        PaddleOcrEngine (root side), paddle_worker.dart (the isolate),
              paddle/ (pre- and post-processing, CTC), OcrModelStore,
              model_verification (SHA-256), UnsupportedOcrEngine, OcrServices
features/ocr/ OcrResultCubit, OcrResultPage (check screen), route /scan/ocr
```

`domain/` imports only Dart and `equatable`; the engine, the image makers and
the work store are ports implemented in `services/`. The scan feature knows the
OCR only through `RecognizePages` and the `OcrSession` it returns; the OCR
feature only through the session passed as the route's `extra`.

### Data flow of one page

```
camera shot (cache JPEG)
   -> OcrSession.add            (returns at once; one page is processed at a time)
   -> PrepareImageForOcr        header (size, EXIF) -> plan:
         <= 8 MP    DartUprightImageMaker   (Isolate.run, package:image)
         <= 400 MP  NativeUprightImageMaker (Kotlin: inSampleSize, rotate, scale;
                    never a full-size decode)
         >  400 MP  refused: OcrFailed(imageTooLarge), nothing decoded
   -> upright working copy (cache/ocr_work, long side <= 2560, JPEG 95)
   -> PaddleOcrEngine.recognize (root isolate: timeout 45 s, cancel, outcome)
   -> worker isolate: verify SHA-256 of the model files, load sessions once,
      decode copy -> detection (960) -> DB boxes -> crops -> recognition
      (batch 1, CPU) -> CTC -> lines with quads normalised to 0..1,
      progress events ("line N of M")
   -> applyConfidenceFilter     (flags lines below 0.65, edits nothing)
   -> OcrSessionSnapshot stream -> OcrResultCubit -> OcrResultPage
```

Sizes are the pixels of the decoded image, never the EXIF size tags. The
header reader returns the SOF size of the stored image and the orientation
(invalid values mean no rotation).

### The isolate

One long-lived worker isolate per engine. It is spawned on the first
`preload` or `recognize`, loads the detector and the recogniser of the chosen
pack once and keeps them. Messages are plain lists. Operations (`load`,
`recognize`, `release`) run one after the other in a queue, so a cancelled page
is finished before the next one starts and two pages never share the memory;
`cancel` is handled at once, between two crops. The root side starts a timer for
the page and listens to the cancellation token; the first of reply, timeout and
cancel decides the outcome. Models are extracted from the APK to
`ocr_models/` in the app support folder by the root isolate (a background
isolate has no `rootBundle`) and verified by the worker (size and SHA-256)
every time they are loaded; a file that fails is deleted so the next run
extracts it again. `release` closes the sessions; `RecognizePages` calls it when
the result screen is left.

### Pipelining (Multi Page)

`ScanCubit` creates an `OcrSession` with the first shot and adds every shot as
soon as the camera has written it. The session reads the pages in capture order
while the next one is photographed; deleting the last shot removes it from the
queue (or cancels it). Done hands the session to the result screen with
`ScanState.ocr`; leaving the scan unsaved disposes it. Opening the camera calls
`preload`, so the first page does not pay for loading the models. A failing or
refused reading never fails the scan: the pictures are stored as before.

### Language pack

`AppSettings.ocrPackId` (key `settings.ocr.pack`), default `greek` for a Greek
device and `latin` otherwise, saved at once from Settings
(`SettingsEditorCubit.selectOcrPack`). The registry holds the SHA-256 and size
of every file; `assets/ocr/manifest.json` holds the same plus the download URLs
and a test keeps the two in step.

### Models and build

The models (about 28 MB for the two packs and the detector) are not in git.
`tool/fetch_ocr_models.sh` downloads them from the pinned URLs of the manifest
and verifies the SHA-256; the Gradle task `verifyOcrModels` is a dependency of
`preBuild`, so a build without them, or with a wrong file, fails with a message
that names the file and the script. `test/services/ocr/ocr_assets_test.dart`
does the same check in `flutter test`.

Release builds run R8 (`isMinifyEnabled`, `isShrinkResources`) with
`android/app/proguard-rules.pro` keeping `ai.onnxruntime.**`. The OCR code uses
no network: a test reads the sources for HTTP clients and sockets, and the
manifest has no `INTERNET` permission.

### Check screen

`/scan/ocr` (button "OCR text (check)" on the scan result): progress as text
and a determinate bar, per line the text, confidence and the position of its
first corner, filtered lines in the error colour with a label, a switch that
draws the quads over the working image, a summary (pack, time, working image,
capture resolution, boxes and filtered), page navigation for Multi Page, and a
button that copies the visible text. Nothing on it animates continuously.

## 9. Testing strategy

| Level | What | Where |
|---|---|---|
| Unit | entities, validators, data source, repository, use cases, cubits, strings, OCR maths (pre/post-processing, CTC), image header and EXIF, model verification | `test/` |
| Widget | whole wizard flow through the real app widget with fakes | `test/features/first_run/` |
| Integration | wizard, settings and scan flows with real rendering on an emulator (fake folder picker, fake camera and folder store); `camera_smoke_test.dart` uses the real camera on the `virtualscene` | `integration_test/` |
| Manual | real SAF picker, real device, visual check | `PHASE_0_VALIDATION.md` |

`integration_test/ocr_engine_test.dart` runs the real models on the emulator
(invented pages: key tokens, coordinates, EXIF, 12 MP, 200 MP header, cancel,
timeout, Multi Page); `integration_test/ocr_release_smoke_test.dart` is the same
engine in a release build.

`integration_test/gallery_copy_test.dart` saves a synthetic picture through the
real `gal` plugin (Gallery file name).

Rules: no personal data in samples or tests (use `example.com` addresses and
synthetic names); fakes live in `test/support/`; platform adapters are always
injected.

## 10. Rust (ADR-002) in Scan

Not used in Phase 0. Candidate areas, to be decided in the image
processing phase: edge detection, perspective correction, contrast
enhancement (CPU heavy, platform independent), and possibly JSON contract
validation if a crate shared with the Budget app is wanted. Camera and OCR
depend on native APIs and stay outside Rust. Costs to weigh then:
`cargo-ndk`, `flutter_rust_bridge`, extra ABIs (arm64 for real devices).

## 11. Platform notes

- Android first. `minSdk 24`. Debug builds for the emulator use the host ABI;
  a real phone needs arm64 (Phase 1 builds and tests on a real device).
- iOS later: implement `StorageFolderPicker` with security-scoped bookmarks and
  keep the rest unchanged.

## 12. Extension points for later phases

| Phase | Adds | Plugs into |
|---|---|---|
| 0.5 | Settings screen, folder health check | feature `settings`, `HomeCubit` |
| 1 | `CameraService`, originals into `./pictures` (done) | `services/camera/` + feature `scan` |
| 2 | `OcrEngine` + Paddle PP-OCRv5, upright working copy, language packs (done, 8d) | `services/ocr/`, `services/image/` |
| 2.1 | Spike: searchable PDF, select and copy a code on the phone | spike only |
| 3 | `PdfGenerator` into `./pdf` (text layer; uses the upright working copy and the line quads) | `services/pdf/` |
| 4 | `MailProvider` (+ implementations) | `services/mail/` |
| 5 | One-click orchestration use case | `domain/usecases/`, feature `scan` |
| 6 | Image enhancement | `services/` (Rust candidate) |
