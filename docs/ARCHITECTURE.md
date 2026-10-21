# Architecture (Phase 0.5)

Status: Phase 0 skeleton compiled and committed; Phase 0.5 adds the settings
screen (see `PHASE_0_VALIDATION.md` and `PHASE_0_5_VALIDATION.md`).

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
├── domain/              entities, repository interfaces, use cases. Pure Dart.
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

## 9. Testing strategy

| Level | What | Where |
|---|---|---|
| Unit | entities, validators, data source, repository, use cases, cubits, strings | `test/` |
| Widget | whole wizard flow through the real app widget with fakes | `test/features/first_run/` |
| Integration | wizard + persistence across a simulated restart, real SharedPreferences, on an emulator | `integration_test/` |
| Manual | real SAF picker, real device, visual check | `PHASE_0_VALIDATION.md` |

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
| 1 | `CameraService`, originals into `./pictures` | `services/camera/` + feature `scan` |
| 1.5 / 2 | `OcrEngine` interface and engine(s) | `services/ocr/` |
| 3 | `PdfGenerator` into `./pdf` (text layer decision) | `services/pdf/` |
| 4 | `MailProvider` (+ implementations) | `services/mail/` |
| 5 | One-click orchestration use case | `domain/usecases/`, feature `scan` |
| 6 | Image enhancement | `services/` (Rust candidate) |
