# Roadmap

Rule: never generate the whole app. Each phase = architecture → plan → code →
unit and integration tests → manual check by the user → wait for confirmation.
Each phase leaves a runnable app. Claude Code implements and never commits or
pushes; the user commits.

Priority: the one-click "SCAN & SEND" by e-mail. JSON export and the Budget link
come second. Scan must work standalone for plain documents. (This order
replaces the original Phase 1–7 order of the project instructions.)

| Phase | Content | Notes |
|---|---|---|
| 0 | Skeleton, DI, routing, settings, wizard (incl. storage folder) | This repo seed |
| 1 | Camera, local save, optional Gallery copy, single/multi page | Build for arm64 and test on a real phone |
| 1.5 | OCR spike with real Greek documents, no production code | Time-boxed. Decides the engine. Real documents stay on the phone: never in repo, prompts or tests. |
| 2 | `OcrEngine` interface + chosen engine, languages | Tests use synthetic documents |
| 3 | PDF generation, single and multi page | |
| 4 | Mail: `MailProvider` interface, direct sending, separate sender account | Auth approach (OAuth vs app password) decided at the start of this phase |
| 5 | One-click SCAN & SEND | Empty OCR: still send the mail with the PDF and notify the user |
| 6 | JSON contract v1, scan type (Receipt/Document), `documentType`, shared folder export | Receipt produces JSON; Document produces PDF only |
| 7 | Soft filter (warning, never blocking) | Minimal check, no copy of Budget's rule engine |
| 8 | Image enhancement: crop, edges, perspective, contrast | Likely Rust candidate |
| 9 | Exposure for Budget (FileProvider, content URIs, package visibility) | No dependency between the apps |
| V1.5 | Batch processing, auto retry, better OCR | Budget limit: 50 files per import |
| V2 | Deeper Budget integration | |

Handwritten, multi-page bills are expected: Single/Multi Page and
Receipt/Document are independent choices.
