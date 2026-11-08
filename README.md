# One Click Scan

An Android app that scans a document with the phone camera, reads it **on the device** (OCR),
makes a PDF and e-mails it, in one tap. Built with Flutter.

> **Status:** active development, not yet on the Play Store. Source is publicly visible for
> review and portfolio purposes only (see [License and contact](#license-and-contact)).

## How it works

```
SCAN & SEND -> capture -> crop and straighten -> OCR (on device) -> PDF -> e-mail
               (originals   (page found and       (Greek + Latin,     (picture of   (SMTP with an
                saved as     cut out for the PDF)  PP-OCRv5 on ONNX)   the page + a   app password, or
                shot)                                                  hidden text    the e-mail app)
                                                                       layer)
```

Inside the folder the user chooses, `pictures/` holds the original JPEGs, exactly as the camera
took them, and `pdf/` holds the PDFs with matching names (`YYYY-MM-DD_HH-MM-SS`). The mail has a
neutral subject (`One Click Scan - <name>`), a one-line body and the PDF. The OCR text is never in the mail.

## Privacy

- OCR runs on the device. There is no cloud service and no telemetry.
- The only network traffic is sending the e-mail to the provider the user picked.
- The original photos are never modified. Cropping, straightening and light correction only
  affect a working copy used for the PDF.
- The mail password is kept in the Android Keystore, outside backups and logs. Logs never
  contain document text, addresses or file names.

## Features

All of these are implemented and were checked on the emulator; the phone checks are
tracked in the `docs/PHASE_*_VALIDATION.md` files.

- **One Click or preview:** the scan is sent at once, or shown first with Send / Discard.
- **Single and Multi Page**, with cancel in every stage (writing pictures, reading, PDF, send).
- **Automatic crop and straightening** of the page for the PDF, with a fallback to the whole
  frame when the detection is not sure. Pure Dart, in a background isolate.
- **OCR in Greek and English** (PaddleOCR PP-OCRv5 on ONNX Runtime), language packs per script.
- **Searchable PDF** with an invisible text layer. This is a best effort, not a promise of exact text.
- **Camera aids:** flash (Off / Auto / On, where On is a flashlight that switches itself off
  after two minutes), tap-to-focus, and a low-light warning. A dark shot
  stops One Click with a choice (retake, continue, or continue with a light correction).
  The shadow removal is only ever applied when the user asks, and it is kept only if the OCR
  reads more words afterwards. A hidden diagnostics screen shows the light numbers.
- **Mail:** SMTP with an app password (Gmail, Yahoo), or the "open in your e-mail app" route.
- **Greek and English UI**, following the device theme.

## Project status

From [`docs/ROADMAP.md`](docs/ROADMAP.md):

| Phase | What | State |
|---|---|---|
| 0, 0.5 | Skeleton, settings, wizard, storage folder | Done |
| 1 | Camera, originals into `pictures/`, Gallery copy, Single/Multi | Done |
| 1.5 to 1.6c | OCR spikes with synthetic documents, timing, crash safety | Done (spikes) |
| 2, 2.1 | OCR in the app, searchable-PDF spike | Done |
| 3 | PDF generation with a text layer | Done |
| 4, 4.1 | E-mail: app password, share route, guide | Done |
| 5, 5.1 | One Click / preview, cancel everywhere, automatic return | Done |
| 6.0 to 6.2.1 | Crop and straighten, flash and flashlight, focus, low light, optional light correction | Done on the emulator, phone check pending |
| 6.3, 6.4 | Small-page option, reading order on tilted pages | Proposals, only if the phone check asks |
| 7 | Review of the Budget integration | Later |
| 8 | Mail OAuth (before any public release) | Planned ([`docs/MAIL_OAUTH_PLAN.md`](docs/MAIL_OAUTH_PLAN.md)) |

"Done on the emulator" means unit, widget and emulator integration tests pass; a check on a real
phone is a separate step recorded in the validation documents.

## Architecture

Clean Architecture in short:

- `lib/domain/`: entities, use cases and **ports** (interfaces). No Flutter, no plugins.
- `lib/services/` and `lib/data/`: implementations of the ports (camera, OCR, PDF, mail, files),
  and the only place plugins appear.
- `lib/features/`: screens with `flutter_bloc` Cubits. Features do not import each other.
- Dependency injection with `get_it`, registered by hand and built fresh per build. Routing with `go_router`.

Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Decisions with their reasons (30 ADRs):
[`docs/DECISIONS.md`](docs/DECISIONS.md).

## Build and run

Needs Flutter (Dart SDK `>=3.13.0 <4.0.0` per `pubspec.yaml`; developed with Flutter 3.47) and the
Android SDK.

```
git clone https://github.com/hedefender/one_click_scan.git
cd one_click_scan
flutter pub get
bash tool/fetch_ocr_models.sh                # needs bash (on Windows: Git Bash)
flutter analyze
flutter test
flutter build apk --debug
```

**OCR models.** About 28 MB of ONNX models and dictionaries are not in git. The script
downloads them from the third-party Hugging Face mirrors pinned by commit in `assets/ocr/manifest.json` and checks each file against a
pinned SHA-256; it fails loudly on a mismatch. Without them the Android build and `flutter test`
fail with a message that names the missing file. The models are under the Apache-2.0 license of
PaddleOCR (see [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md)).

**Tests.** `flutter test` runs 1178 unit, cubit and widget tests (they need the models, nothing else).
Integration tests (`integration_test/`) run on an Android emulator; `tool/run_integration_test.sh <device-id> <test file>`
installs the app, grants the camera permission and runs one test. Release smoke test (R8 on): `tool/run_ocr_release_smoke.sh <device-id>`.
Use an Android emulator or a device you do not mind installing test builds on.

## E-mail setup

- **Gmail and Yahoo:** create an app password with the provider and enter it in Settings.
  The app has an in-app guide that opens the provider's page. Details: [`docs/MAIL_PROVIDERS.md`](docs/MAIL_PROVIDERS.md).
- **Backup route:** "Open in e-mail app" opens the provider's own mail app with the PDF attached.
- **Outlook.com:** for now only through the backup route.
- **Later:** official sign-in (OAuth) is planned, see [`docs/MAIL_OAUTH_PLAN.md`](docs/MAIL_OAUTH_PLAN.md).

## Known limitations

- The PDF text layer is best effort. It does not promise exact characters, so do not rely on it
  for payment codes.
- The package id is a placeholder (`com.example.one_click_scan`).
- Tested mainly on one Android phone and on an emulator; `minSdk` is 24. iOS is not implemented.
- The real flash, real room light and real lens behaviour cannot be tested on the emulator.
  The low-light threshold is a starting value to be calibrated on a phone.
- The OCR models are downloaded from third-party mirrors until the project hosts its own release.
- No store release yet.

## Development workflow

Each phase starts with an architecture note and, for risky choices, a spike with numbers
(`docs/*_SPIKE_RESULTS.md`), then a plan, code and tests. The code is written with an AI coding
assistant (Claude Code) under written rules ([`CLAUDE.md`](CLAUDE.md)); the assistant never commits,
and every phase ends with a manual check on a real device before the next one starts. There are
1178 automated tests. The checks are in [`docs/PHASE_6_2_VALIDATION.md`](docs/PHASE_6_2_VALIDATION.md)
and its siblings; the document index is [`docs/README.md`](docs/README.md).

## License and contact

**All rights reserved.** The source is publicly visible for review and portfolio purposes only.
See [`LICENSE`](LICENSE). Nobody may use, copy, modify or distribute this code or any part of it
without prior written permission.

If you would like to use the code or part of it, ask the copyright holder, Stefan Paraskevas:
[LinkedIn](https://www.linkedin.com/in/stefan-paraskevas-a98992162/) or through the GitHub profile
of [`hedefender`](https://github.com/hedefender).

Third-party components keep their own licenses: [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md).
