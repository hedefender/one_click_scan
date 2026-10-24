# Phase 2.1: searchable PDF spike, results

Spike in `spikes/pdf_spike/` (not the app). Question: can a PDF carry invisible
text under the page picture, so that a viewer can search, select and copy it, in
particular a payment code (RF, IBAN), **without a wrong, missing or added
character**? All documents are invented. Numbers marked **[emulator]** come from
the Claude Code emulator (`Claude_Code_Test`, x86_64, 2 GB) and PC tools; numbers
for the phone are still to be filled in from `PHASE_2_1_VALIDATION.md`.

## 1. What was built and how it was measured

- **Choice of project:** a separate project `spikes/pdf_spike/` (option α). Reason:
  the spike needs the OCR plus something the production engine does not return
  yet (the position of every character), and it needs its own Android bits (open
  and share a PDF). A development screen in the main app (option β) would have
  put spike code, a font asset and two plugins into `lib/` and into the release
  APK for a throw-away experiment. The OCR code was copied and trimmed
  (`lib/ocr/`: root isolate, no cancel, no SHA-256) and extended with
  `ctcWithSteps`; `lib/` of the app is untouched.
- **Layouts** (`lib/pdf/layout.dart`): **A** one run per OCR line, stretched to the
  box width; **B** one run per word, each word placed from the CTC time steps of
  its characters; **C** like B, but a word that contains a digit is one run per
  character.
- **Writers** (same layouts, same page): **lib** = package `pdf` (dart_pdf 3.13.1),
  invisible text (render mode 3) in Noto Sans, subset by dart_pdf; **glyphless**
  = own writer, a TrueType font generated in Dart that has only box glyphs,
  Type 0 / Identity-H / `ToUnicode`; **type3** = own writer, a Type 3 font with
  no font file.
- **Documents:** 7 payment sheets (RF code, IBAN, amounts, invoice numbers, Greek
  and English, type sizes 22 to 54 px; two of them tilted +2.5° and -1.5° with
  camera-like noise), a 24-line receipt, a 44-line dense page, and a 3-page PDF.
  Rendered with the system font, with the true position of every character
  recorded.
- **Automatic measurement on the PC** (`tool/analyze.py`, PyMuPDF and pypdf, also
  `pdftotext`): valid PDF, no EXIF/GPS, extracted text equals the OCR text,
  position error per character, and a simulated drag selection (see 3).
- **In a real viewer:** the emulator has the Google Drive PDF viewer (PDFium
  based). A script (`tool/drive_viewer.sh`) opens the PDF, long-presses the code,
  taps Copy, and the spike reads the clipboard and compares it with the invented
  code. This is the only real viewer measured so far.

## 2. Answers to the questions

### 2.1 Invisible text from Dart

| Question | Answer |
|---|---|
| Does `pdf` (dart_pdf) write text render mode 3? | Yes: `PdfTextRenderingMode.invisible` in `drawString`/`TextStyle.renderingMode`. It also subsets the TrueType font and writes `ToUnicode`. |
| Alternative | Writing the PDF by hand is easy (about 300 lines, `raw_pdf_writer.dart`): page image as a DCT stream, text with `3 Tr`, a Type 0 or Type 3 font, `ToUnicode`. Needs no package. |
| Unicode / copy | Greek with accents, Latin, digits, `·`, `@`, `,` came out identical in PyMuPDF, `pdftotext` and in the viewer's clipboard for all writers (extracted text equals the OCR text in 81 of 81 PDFs). |
| Fonts and sizes | See 2.2. |
| Page picture | The upright working copy (JPEG, long side ≤ 2560, quality 90, written by the `image` package: no EXIF, no GPS, no XMP). The PDF has no `/Info` (no author, producer, date). Checked in all 81 PDFs: no `Exif`, no `GPS`, no APP1/APP13/COM marker in the embedded picture. |
| Multi page | Works: 3 pages, 3 images, 45 words per page extracted, 399 to 409 KB **[emulator]**. |

### 2.2 Font, Unicode and size cost

| Approach | Cost per PDF (text layer on top of the JPEG) | Scripts | Notes |
|---|---|---|---|
| `lib`: Noto Sans subset (dart_pdf) | +9 to 17 KB (sheet 12 KB, receipt 11 to 13 KB, dense 9 to 17 KB); the subset font stream alone is about 8.5 KB compressed for the 70 glyphs of a sheet | Latin, Greek, Cyrillic (what the font has) | Needs the font file in the app: Noto Sans Regular is 621,572 B (313,027 B deflated). SIL OFL 1.1: embedding in documents (also subsets) is allowed; the app would have to ship the licence text. Another script needs another font. |
| Embedding the whole font | would add about 313 KB (deflated) per PDF | | Not offered by dart_pdf (it always subsets); computed from the file. Not recommended. |
| `glyphless`: generated TrueType with box glyphs | **+4.6 to 10 KB** (sheet 5 KB, receipt 5 to 7 KB, dense 5 to 10 KB) | **any script**: the font has no shapes, `ToUnicode` carries the text, one font for up to 60,000 distinct characters | No font asset, no font licence. About 1 to 3 KB of font. Own code to maintain. |
| `type3` | +14 to 17 KB (one small stream per glyph, not shared) | any script, 250 characters per font | Works, but biggest and most special. |

**Glyphless is possible in Dart, with one condition found by measurement:** the
glyphs must not be empty. With truly empty glyphs (no outline, no box) the
viewer showed the page correctly but **would not select the text at all**, for
both the Type 3 and the TrueType variant (checked after force-stopping the
viewer between runs, so no leftover state). Giving every glyph an outline
(a rectangle as wide as the character and one em high, shared between glyphs of
equal width) fixed it. The box is never painted, because the text is rendered
with mode 3 (invisible). This is the same trick, in another form, as the
glyphless font of OCRmyPDF/Tesseract.

Typical PDF sizes **[emulator, synthetic pages with camera-like noise]**:

| Page | JPEG | PDF (glyphless B) | PDF (lib B) |
|---|---|---|---|
| payment sheet (1240 x 745) | 129 KB | 134 KB | 141 KB |
| receipt, 24 lines (1240 px wide) | 608 KB | 613 KB | 620 KB |
| dense page, 44 lines | 1,164 KB | 1,174 KB | 1,180 KB |
| 3 pages | | 399 KB | 407 KB |

A real photographed receipt at 2560 px will be 0.5 to 1.5 MB as a JPEG; the text
layer adds 5 to 17 KB, under 2% on a real page. The phone numbers for a real
receipt are asked in `PHASE_2_1_VALIDATION.md` step 4.

### 2.3 Time to make the PDF

**[emulator, in a background isolate, includes writing]**: 3 to 50 ms per PDF for
every variant (the JPEG is passed through as it is). The cost of the page is the
OCR (1.0 to 1.8 s a sheet or receipt, 6.8 s the dense page on the emulator), not
the PDF. Phone values: from the `PDFSPIKE pdf ...` lines of step 1.

### 2.4 What the OCR engine must return

`OcrLine.charBoxes` (empty in Phase 2) must be filled. The spike shows the cost is
small: **no extra inference**. The CTC greedy decode already knows, for every
emitted character, the time step(s) where it appeared (`ctcWithSteps`, about 20
lines more than `ctcGreedy`); a step is a fixed share of the box width. A
character's extent is the span between the midpoints of neighbouring characters.
That gives, per line, one `(x0, x1)` pair per character (fractions of the box
length). Added data: 2 numbers per character (about 7,400 numbers for a dense
page). The Phase 2 contract needs one field: `OcrLine.charBoxes` as quads built
from the box and these fractions.

## 3. Placement and selection accuracy

### 3.1 Position error (share of the character width, **[PC analysis of PDFs from the emulator]**)

7 payment sheets, about 1,050 aligned characters per variant (invented text,
known true positions):

| Layout | writer | mean | median | p95 |
|---|---|---|---|---|
| A (line) | glyphless / type3 (approximate width table) | 39% | 29% | 106% |
| A (line) | lib (real Noto Sans widths) | 21% | 19% | 47% |
| B (word, CTC) | glyphless / type3 | 18% | 15% | 46% |
| B (word, CTC) | lib | 15% | 13% | 36% |
| C (char for codes) | glyphless / type3 | 14% | 11% | 39% |
| C (char for codes) | lib | 13% | 10% | 34% |

For the two tilted sheets (+2.5° and -1.5°, noise) the numbers are the same within
2 points (B: 20% and 17%). So the CTC positions are good to about 15% of a
character on average and 35 to 45% at the 95th percentile.

### 3.2 Simulated drag selection

A drag over part of a line: the characters whose centre lies between the two ends
are selected. Targets: every token with a digit of 6 or more characters (RF code,
IBAN, invoice, meter and customer numbers) and 8 random sub-ranges of 5 to 18
characters inside each; 25 drags each; **11,025 drags per variant**. "Perfect
aim" starts and ends exactly on the true character edges; "±¼ char" adds a
random error of up to a quarter of a character at each end.

| Layout | writer | exact, perfect aim | exact, ±¼ char | missing a char | extra char | wrong |
|---|---|---|---|---|---|---|
| A | glyphless / type3 | 75.7% | 68.7% | 9.5% | 16.0% | 5.8% |
| A | lib | 90.0% | 85.7% | 7.3% | 5.3% | 1.7% |
| **B** | glyphless / type3 | 97.1% | 91.7% | 2.3% | 5.7% | 0.3% |
| **B** | lib | **99.8%** | 97.0% | 0.6% | 2.4% | 0.0% |
| C | glyphless / type3 | 100.0% | 98.1% | 0.7% | 1.2% | 0.0% |
| C | lib | 100.0% | 98.1% | 0.7% | 1.2% | 0.0% |

Reading: with a line per run (A) a partial selection of a code is wrong in 1 of 4
or 1 of 3 cases (the width of each character is only a model of the font). Per word
(B) it is wrong in about 1 of 40 with perfect aim, and what is left is mostly the
imprecision of the finger. Per character (C) the PDF itself adds no error; the 2%
left is the simulated finger. These are simulations of the positions in the PDF,
not of a viewer's own snapping rules.

### 3.3 In a real viewer (Google Drive viewer, emulator), long-press on the code

One run per cell, clipboard cleared before, viewer force-stopped between runs.
The code is the whole 23-character RF code or 27-character IBAN.

| Writer / layout | A | B | C |
|---|---|---|---|
| lib (Noto subset) | RF exact, IBAN exact | RF exact, IBAN exact | RF exact, IBAN exact |
| glyphless (box glyphs) | RF exact, IBAN exact | RF exact, IBAN exact | **RF: 3 characters, IBAN: 1 character** |
| type3 (box glyphs) | RF exact, IBAN exact | RF exact, IBAN exact | RF exact, **IBAN: nothing** |

- **A and B work in all three writers.** A long-press on a word of the page picks
  the whole word (the code) and Copy gives it exactly.
- **C is fragile:** with one text object per character the viewer's long-press
  can select only a single character or nothing. C is not suitable as the way to
  select a whole code (it is only useful if a viewer cannot handle B).
- **Empty glyphs: not selectable** (see 2.2).
- Highlight geometry: the blue selection of the `lib` B file covers exactly the
  code on the page (screenshot checked).
- Not measured: Chrome, Acrobat Reader, the Xiaomi viewer, Gmail's preview. They
  are in `PHASE_2_1_VALIDATION.md`. Every viewer has its own rules for words,
  snapping and invisible text, so this table is a lower bound of the work, not a
  result for the phone.

## 4. Risks and things the numbers do not say

1. **The OCR can still read a wrong character.** In the 7 sheets all 42 long digit
   tokens (RF, IBAN, invoice and meter numbers) were read exactly, but words
   next to them came out with a Greek look-alike inside Latin text (`2Ο26` with a
   Greek capital omicron, `ΕUR` with a Greek epsilon). A code that contains
   letters can suffer from the same confusion with the Greek pack. A hidden layer
   copies what the OCR read, so the PDF cannot be better than the OCR. ADR-013
   (the scanner never edits the text) stays, so the protection has to be a **check**,
   not a correction: RF codes and IBAN have check digits (ISO 7064 mod 97-10);
   verifying them tells the user, or Budget, that a copied code fails the
   checksum. Proposed for Phase 3 or later; not built.
2. **One real viewer, one run per cell.** Chrome, Acrobat, the Xiaomi viewer and
   the Gmail preview are untested; the box-glyph finding shows viewers differ in
   what they need. The phone table is required before the decision.
3. **Line breaks of a whole-page copy.** `pdftotext` merged some neighbouring
   lines into one when the whole page is extracted (for example the code line and
   the IBAN line). It does not affect selecting a code, but "copy all" may join
   lines. A cleaner baseline and a font-size derived from the line height would
   help; not tuned.
4. **A code split across two OCR boxes** (a large gap in the middle, or a line
   break) would be two runs; a word-level selection then gets one half. The
   detector produced one box per code in all 7 sheets.
5. **Positions are estimates:** CTC steps are about 8 px wide in the recogniser
   input and the peak of a character is not its centre; the 15% average and the
   p95 of 35 to 45% are the cost. Vertical placement uses a fixed baseline share
   of the box (22% above the bottom) and a font size of 72% of the box height.
6. **The font:** dart_pdf with Noto Sans has no Arabic, Hebrew, CJK or Indic glyphs
   (future packs). Glyphless has no such limit.
7. **Rotation:** the page picture is upright (EXIF applied before). A line rotated
   inside the picture (tilt) is handled (the run is rotated with the box); a
   90° line would not be.

## 5. Proposal for Phase 3

1. **Writer:** start with the **glyphless writer** (own code, 5 to 10 KB overhead,
   any script, no font asset or licence) and keep the `pdf` package with a Noto
   subset as the proven alternative: both pass in the viewer measured. The
   decision is made from the phone table (Chrome, Acrobat, Xiaomi, Gmail): if
   glyphless fails on a viewer that matters while `lib` works, use `lib` (and
   bundle the font for Greek, Latin, Cyrillic).
2. **Granularity: B, one run per word.** Selection of a whole code by long-press is
   exact in the viewer, and a partial drag is exact in 97 to 99.8% of 11,025
   simulated drags (A: 69 to 90%). Do not use C as the default.
3. **Engine:** return `charBoxes` (the CTC step positions; no extra inference;
   `ctcWithSteps`), one list of `(x0, x1)` fractions per line; use them for the word
   boundaries only.
4. **Page image:** the Phase 2 working copy (JPEG ≤ 2560, no EXIF, no GPS) passed
   through into the PDF unchanged. The PDF is the JPEG plus 5 to 17 KB.
5. **Safety net:** a check-digit test of RF and IBAN codes (warn, never edit);
   leave the decision to the user after seeing real documents.

## 6. Not checked

- Any viewer other than the emulator's Drive viewer; handle-drag partial selection
  in a real viewer (only simulated); the phone's PDF times and sizes; a real
  photographed receipt; Cyrillic and Latin-accent lines with the other packs;
  PDFs with more than 60,000 distinct characters (not realistic).
