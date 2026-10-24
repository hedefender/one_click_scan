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
| 1.6b | Controlled phone measurements (UI load A/B, provider x threads, provider accuracy, best preset) and language-pack inventory, spike and docs only | **Tooling done and checked on the emulator; phone numbers by the user pending** (`PHASE_1_6_VALIDATION.md`). Results: `OCR_SPIKE_RESULTS.md` section 10; `OCR_LANGUAGE_PACKS.md` |
| 1.6c | Spike crash on a 200 MP sample, safe harness (size guard, breadcrumb and resume, wake lock, exit reasons), paired A/B, language-pack measurements | **Done on the emulator; phone repeat of A to D and the paired test by the user pending** (`PHASE_1_6_VALIDATION.md`). Results: `OCR_SPIKE_RESULTS.md` section 11; `OCR_LANGUAGE_PACKS.md` |
| 2 | OCR in the app: `OcrEngine` + Paddle PP-OCRv5 (background isolate), language packs, upright working copy, check screen | **Done on the emulator; phone check by the user pending** (`PHASE_2_VALIDATION.md`). Architecture: `ARCHITECTURE.md` 8d; decisions ADR-010 to ADR-014; third-party licences `THIRD_PARTY_NOTICES.md`. No PDF, no mail, no JSON |
| 2.1 | Spike: searchable PDF on the phone (hidden text under the picture): can the user select and copy a code such as an RF code? Decides whether per-character boxes (`OcrLine.charBoxes`, empty in Phase 2) are needed | **Done on the emulator and the PC; phone viewer table by the user pending** (`PHASE_2_1_VALIDATION.md`). Results: `PDF_SPIKE_RESULTS.md`. Hidden text works in the emulator's viewer for per-line and per-word layouts, with a Noto subset (`pdf` package) and with a generated glyphless font (glyphs must not be empty); per-word is the proposal; `charBoxes` are needed (from the CTC time steps, no extra inference). Spike in `spikes/pdf_spike/` |
| 3 | PDF generation (single and multi page) into `./pdf` | Decision on the text layer, see "Open decisions" |
| 4 | Mail: `MailProvider` interface, direct sending, separate sender account | Auth approach (OAuth vs app password) decided at the start of this phase |
| 5 | One-click SCAN & SEND | Empty OCR: still send the mail with the PDF and notify the user |
| 6 | Image enhancement: crop, edges, perspective, contrast | Likely Rust candidate. Findings of the first phone check of Phase 2 (receipt 3060x4080, tilted, blurred, with a shadow): (1) in bold capitals the reading made mistakes (for example one word read as two different wrong words) and small faded text was lost, so better capture (focus, light) and perspective and contrast correction belong here; (2) on a tilted page the reading order paired a label with the wrong value (a net-amount label got the 0,00 that belonged to the discount line), so lines must be grouped with a tolerance for the tilt (estimate the angle and rotate the coordinates before grouping) or the page deskewed before the OCR; (3) check whether the capture waits for autofocus lock before the shutter. (The request called this "Phase 4"; in this table image enhancement is Phase 6, Phase 4 is Mail.) |
| 7 | Revisit the Budget integration (only if Scan needs to change something) | No dependency between the apps |
| V1.5 | Batch processing, auto retry, better OCR | Budget limit: 50 files per import |

Handwritten, multi-page bills are expected: Single/Multi Page is an independent
choice.

## Open decisions

- **Phase 3 proposal (from Phase 2.1, `PDF_SPIKE_RESULTS.md` section 5; decided after the
  phone viewer table).** Writer: own glyphless writer (5 to 10 KB, any script, no
  font asset) with the `pdf` package plus a Noto Sans subset as the alternative;
  layout: one hidden run per word; the engine returns `charBoxes` from the CTC
  time steps; the page image is the Phase 2 working copy passed through; a
  check-digit test of RF and IBAN codes (warn, never edit) as a safety net.

- **Searchable PDF vs Budget OCR (decided in Phase 3).** For Budget to read text
  from a PDF, either the Scan PDF carries an invisible text layer (searchable
  PDF), or Budget runs its own OCR. Not decided yet.
- **Receipt/Document choice, soft filter, `documentType` (decided in the OCR
  phase).** They existed for the JSON export. With no JSON (ADR-008) they are
  suspended and not implemented. They come back only if the OCR phase finds a
  use for them.
- **Theme.** Always follows the device theme. No theme option is planned.
