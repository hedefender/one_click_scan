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
| 3 | PDF generation (single and multi page) into `./pdf`, with a best-effort text layer, and an Open PDF button | **Done on the emulator; phone check by the user pending** (`PHASE_3_VALIDATION.md`). One PDF per scan, `pdf/<stem>.pdf` (ADR-015); the picture is the Phase 2 working copy at 200 dpi (ADR-017); the hidden text is one piece per word in Noto Sans, a free extra with no promise of exact copying (ADR-016); no picture stays in the cache (ADR-018). Architecture: `ARCHITECTURE.md` 8e. No mail, no JSON |
| 4 | Mail: `MailSender` / `MailProvider`, SMTP with an app password (Gmail, Outlook.com, Yahoo), a Send button on the result screen, the share route (open the e-mail app) as the way out, the plan for OAuth | **Done on the emulator; phone check by the user pending** (`PHASE_4_VALIDATION.md`). Facts and sources: `MAIL_PROVIDERS.md`; OAuth plan: `MAIL_OAUTH_PLAN.md`; decisions ADR-019 to ADR-023; architecture `ARCHITECTURE.md` 8f. Subject `One Click Scan - <stem>`, no OCR text in the mail. Outlook.com app passwords are NOT confirmed to work, Yahoo has no OAuth that could be confirmed. No automatic send, no automatic retry |
| 4.1 | Share route opens the provider's own e-mail app, diagnostic line on failures, one-tap backup way, app password guide per provider | **Done on the emulator; phone check by the user pending** (`PHASE_4_VALIDATION.md` steps 12 to 15). Decision ADR-024; facts and sources `MAIL_PROVIDERS.md` (Phase 4.1). The three app package names are **not** confirmed from an official page (the Play pages could not be read); the install check and the `mailto:` fallback make that safe. User's phone check of Phase 4: the share route to Gmail and SMTP with a Gmail app password worked; the failures before were the normal password with MFA on |
| 5 | One-click SCAN & SEND: One Click or preview with Send / Discard, chosen in the wizard and in Settings | **Done on the PC (unit, cubit and widget tests); the emulator integration run and the phone check are pending** (`PHASE_5_VALIDATION.md`). Decisions ADR-025 to ADR-027; architecture `ARCHITECTURE.md` 8g. Empty OCR still sends the mail with the PDF. No queue and no automatic retry (V1.5). Discard deletes only by recorded URI; the Gallery copy is now written natively to get a URI (`gal` only asks the permission) |
| 5.1 | Cancel in every stage (pictures written, text, PDF, send), Back = Cancel with a question, a clean screen after Discard, automatic return home 10 s after a sent message (ADR-028); measurements of 5 and 21 pages | **Done on the emulator; phone check by the user pending** (`PHASE_5_VALIDATION.md` section 10). Measured on the x86 emulator, the shots taken back to back (OCR running behind): 5 pages: 8.2 s after Done (store+Gallery 1.6 s, reading+PDF 6.6 s), memory end 620 MB, peak 671 MB; 21 pages: 27.3 s after Done (store+Gallery 3.0 s, reading+PDF 24.3 s), memory end 543 MB, peak 692 MB. These feed Phase 6. |
| 6 | Image enhancement: crop, edges, perspective, contrast | Likely Rust candidate. Findings of the first phone check of Phase 2 (receipt 3060x4080, tilted, blurred, with a shadow): (1) in bold capitals the reading made mistakes (for example one word read as two different wrong words) and small faded text was lost, so better capture (focus, light) and perspective and contrast correction belong here; (2) on a tilted page the reading order paired a label with the wrong value (a net-amount label got the 0,00 that belonged to the discount line), so lines must be grouped with a tolerance for the tilt (estimate the angle and rotate the coordinates before grouping) or the page deskewed before the OCR; (3) check whether the capture waits for autofocus lock before the shutter. (The request called this "Phase 4"; in this table image enhancement is Phase 6, Phase 4 is Mail.) **Also: processing in the background while shooting (reading, and perhaps the PDF, during the capture): decide from the measurements of Phase 5.1** (21 pages took about 27 s after Done on the emulator, most of it the reading and the PDF). |
| 7 | Revisit the Budget integration (only if Scan needs to change something) | No dependency between the apps |
| 8 | **Mail OAuth and public release readiness** (milestone: done **before any public release**) | Replaces the app password with the official sign-in of Google (`gmail.send`) and Microsoft (Graph `Mail.Send` or SMTP XOAUTH2); Yahoo stays on app password or share. Needs the final package id, a release signing key, a public privacy policy, a homepage, a demo video, a Google verification that can take months (`MAIL_OAUTH_PLAN.md` sections 5 and 6). The non-code items should start early and in parallel **Also: the first-run wizard gets the app password step, a guide per provider, and an explanation for Outlook/Hotmail** (why the app password may not work there). |
| V1.5 | Batch processing, auto retry, better OCR | Budget limit: 50 files per import |

Handwritten, multi-page bills are expected: Single/Multi Page is an independent
choice.

## Open decisions

- **Phase 3 (decided and built; was the proposal of Phase 2.1,
  `PDF_SPIKE_RESULTS.md` section 5).** The `pdf` package with a Noto Sans
  subset (not the glyphless writer), one hidden piece per word, the engine
  returns `charBoxes` from the CTC time steps, the page picture is the Phase 2
  working copy passed through. The check-digit test is in the backlog below.

- **Searchable PDF vs Budget OCR (decided in Phase 3).** The Scan PDF carries an
  invisible text layer as a best effort (ADR-016); it is not a promise, so
  Budget cannot rely on it being complete or exact. Whether Budget reads that
  layer or runs its own OCR is for the Budget side to decide (ADR-003: the apps
  stay independent).
- **Receipt/Document choice, soft filter, `documentType` (decided in the OCR
  phase).** They existed for the JSON export. With no JSON (ADR-008) they are
  suspended and not implemented. They come back only if the OCR phase finds a
  use for them.
- **Theme.** Always follows the device theme. No theme option is planned.

## Backlog (frozen until users ask for them)

Ideas that came out of the phases so far. None is started; each waits for a
real request.

- **Check digits (mod 97) of RF and IBAN codes** found in the text: a warning
  when the digits do not add up, never a correction (ADR-013).
- **Per-character hidden text** (a piece per character, for exact partial
  selection with the handles of a viewer). Phase 2.1 measured it as better for
  codes in some viewers and worse in others; not needed for the per-word layout.
- **The "glyphless" PDF writer** of the Phase 2.1 spike (5 to 10 KB per page
  of text layer, any script, no font asset). The `pdf` package with the Noto
  Sans subset does the job today.
- **More language packs by download** (Russian and others), from our own
  hosting with a pinned SHA-256 (ADR-011, `OCR_LANGUAGE_PACKS.md`).
- **Models rebuilt from the official weights** with `paddle2onnx` and hosted on
  GitHub Releases of this project, **before any public release**, so the chain
  has no third-party link (`THIRD_PARTY_NOTICES.md`).
- **Check of the 0.65 confidence threshold on handwriting** (step 9 of
  `PHASE_2_VALIDATION.md`): numbers from real documents, kept on the phone.
- **Share button for the PDF** (ACTION_SEND) next to Open. The mail route of
  Phase 4 already shares the PDF by e-mail (`shareDraft`); a general share to any
  app would reuse `DraftSharer`.
- **Several recipients in the UI** (the domain takes a list, the screens show one).
- **A real SAF check of the mail attachment** on the phone (the tests use a plain
  folder for the stored PDF): step in `PHASE_4_VALIDATION.md`.
- **Hidden text for symbols outside Noto Sans** (arrows, mathematical symbols,
  Roman-numeral glyphs): today they are left out.
