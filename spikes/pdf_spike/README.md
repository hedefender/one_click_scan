# pdf_spike (Phase 2.1)

Spike, not the app. Question: can a PDF carry invisible text under the page
picture so that a viewer can search, select and copy it (for example an RF
payment code) without a wrong character? Results: `docs/PDF_SPIKE_RESULTS.md`,
steps for the phone: `docs/PHASE_2_1_VALIDATION.md`.

- `lib/ocr/`: a trimmed copy of the OCR of the main app, plus the position of
  each character (CTC time steps) that the main app does not return yet.
- `lib/pdf/`: the layouts (A per line, B per word, C per character for codes)
  and three writers: `lib` (package `pdf`, Noto Sans subset), `glyphless` (own
  writer, generated TrueType with box glyphs), `type3` (own writer, Type 3 font).
- `lib/sheet/`: invented documents and the truth of where each character is.
- `tool/analyze.py`, `tool/summarize.py`: measurements with PyMuPDF and pypdf on
  the pulled `out` folder; `tool/drive_viewer.sh`: drives the emulator's PDF
  viewer (Claude_Code_Test only).
- Setup: `tool/fetch_assets.sh` (models are copied from the main app's assets,
  the test font is downloaded). Build: `flutter build apk --release`.
- `--dart-define=AUTORUN=cmd` makes the app obey `out/command.txt` (`bench`,
  `open <file>`, `clip <expected>`), used on the emulator.
