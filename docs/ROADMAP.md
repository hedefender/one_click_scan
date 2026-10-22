# Roadmap

Rule: never generate the whole app. Each phase = architecture → plan → code →
unit and integration tests → manual check by the user → wait for confirmation.
Each phase leaves a runnable app. Claude Code implements and never commits or
pushes; the user commits.

Priority: the one-click "SCAN & SEND" by e-mail. Scan works standalone for plain
documents. Scan produces **no JSON** (ADR-008): Budget reads the PDFs directly.
(This order replaces the original Phase 1–7 order of the project instructions
and the order of the first roadmap.)

| Phase | Content | Notes |
|---|---|---|
| 0 | Skeleton, DI, routing, settings, wizard (incl. storage folder) | Done |
| 0.5 | Settings screen + storage folder health check | Language, folder, e-mail, Gallery switch. Banner on home when folder access is lost |
| 1 | Camera, saving originals to `./pictures`, optional Gallery copy, Single/Multi page | Build for arm64 and test on a real phone |
| 1.5 | OCR spike with real Greek documents, no production code | **Done (synthetic part); real-phone check by the user pending.** Result: `OCR_SPIKE_RESULTS.md`. Recommends PaddleOCR PP-OCRv5 (ONNX Runtime), Tesseract as fallback. Real documents stay on the phone: never in repo, prompts or tests |
| 1.6 | OCR timing profile and Paddle optimisation, spike only | **Done on the emulator (stage shares, accuracy guard, UI stalls); phone numbers by the user pending** (`PHASE_1_6_VALIDATION.md`). Result: `OCR_SPIKE_RESULTS.md` section 9. Dart stays (no Rust or native code needed on current evidence) |
| 2 | OCR: `OcrEngine` interface + chosen engine, languages | Tests use synthetic documents. Proposed engine: PaddleOCR (detection + per-language recognition on ONNX Runtime), behind `OcrEngine` so Tesseract stays a cheap fallback; interface sketch in `OCR_SPIKE_RESULTS.md` §7. Upright pixels in, EXIF baked by the caller. Confirm with the user's phone numbers first |
| 3 | PDF generation (single and multi page) into `./pdf` | Decision on the text layer, see "Open decisions" |
| 4 | Mail: `MailProvider` interface, direct sending, separate sender account | Auth approach (OAuth vs app password) decided at the start of this phase |
| 5 | One-click SCAN & SEND | Empty OCR: still send the mail with the PDF and notify the user |
| 6 | Image enhancement: crop, edges, perspective, contrast | Likely Rust candidate |
| 7 | Revisit the Budget integration (only if Scan needs to change something) | No dependency between the apps |
| V1.5 | Batch processing, auto retry, better OCR | Budget limit: 50 files per import |

Handwritten, multi-page bills are expected: Single/Multi Page is an independent
choice.

## Open decisions

- **Searchable PDF vs Budget OCR (decided in Phase 3).** For Budget to read text
  from a PDF, either the Scan PDF carries an invisible text layer (searchable
  PDF), or Budget runs its own OCR. Not decided yet.
- **Receipt/Document choice, soft filter, `documentType` (decided in the OCR
  phase).** They existed for the JSON export. With no JSON (ADR-008) they are
  suspended and not implemented. They come back only if the OCR phase finds a
  use for them.
- **Theme.** Always follows the device theme. No theme option is planned.
