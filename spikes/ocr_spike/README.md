# ocr_spike

Throw-away spike for Phase 1.5 of Scan: compares ML Kit, Tesseract and
PaddleOCR PP-OCRv5 on synthetic and real documents, offline. Not part of the
app and not production code. Results: `docs/OCR_SPIKE_RESULTS.md`.

- First run `tool/fetch_assets.sh` (downloads about 100 MB of models,
  traineddata and fonts; they are bundled as assets and not committed).
- Android only. The release manifest has no network permission.
- Real-document mode keeps typed values and recognised text in memory only;
  nothing is logged, saved or copied except the "Copy summary" numbers.
- `--dart-define=AUTORUN=full|quick|one|big|tune|exif` runs the synthetic
  benchmark at start and prints `OCRBENCH` JSON lines (synthetic data only);
  `--dart-define=DUMP=true` also prints the synthetic recognised text.
