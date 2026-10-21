# Phase 0 implementation plan

Goal: a runnable skeleton with the full architecture, DI, routing, settings
storage and the first-run wizard. No camera, OCR, PDF, JSON or mail yet.

## Steps (in order)

1. Create the Flutter project (`one_click_scan`, Android only, org `com.example`)
   and overlay the seed files.
2. Resolve dependencies, tighten version constraints, `flutter analyze` clean.
3. Compile. Fix whatever the uncompiled seed needs; list every change.
4. Run unit and widget tests (`flutter test`).
5. Build and install the debug APK on **Claude Code's own emulator**.
6. Run the integration test on that emulator.
7. Stop. The user performs the manual check (`PHASE_0_VALIDATION.md`) on their
   own emulator/phone and commits.

## Scope

| In | Out (later phases) |
|---|---|
| Clean architecture layers, feature modules | Camera (Phase 1) |
| get_it container, go_router | OCR (1.5, 2) |
| Settings (shared_preferences behind an interface) | PDF (3) |
| EL/EN strings, theme | Mail sending, credentials (4) |
| 4-step wizard incl. SAF folder picker | One-click flow (5) |
| Home placeholder with disabled-style SCAN & SEND | JSON, scan types, soft filter (6+) |

## Acceptance criteria

- `flutter analyze`: no issues.
- `flutter test`: all green.
- Integration test: green on the emulator.
- App launches; first launch shows the wizard; after Finish shows home; second
  launch skips the wizard.
- Real folder picker works on a device and the choice survives a restart.
- No personal data anywhere in code, tests, logs or docs.

## Risks and how they are handled

| Risk | Handling |
|---|---|
| Seed was never compiled | Claude Code compiles and reports every fix |
| Package versions unknown | `any` in pubspec, then `dart pub upgrade --tighten` |
| SAF code is native and untestable in Dart | Thin MainActivity, interface in Dart, manual check on a real device |
| Package id placeholder (`com.example.one_click_scan`) | Decide the final id before any release; it must be fixed before publishing |
