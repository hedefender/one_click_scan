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

## Phase 1.6 (performance)

- The **Perf** button (top right) opens the timing lab: experiments x three
  invented scenarios (receipt, dense page, poor quality; also 12 MP versions),
  cold and warm numbers, stall of the UI isolate. "Copy summary" copies numbers
  only. `tool/make_rec_variants.py` derives `rec_<k>_am.onnx` (needs `pip
  install onnx`) after `tool/fetch_assets.sh`.
- Emulator runs: build with `--dart-define=AUTORUN=file --dart-define=DEVICE=emulator`,
  push `autorun.txt` (`mode=perf|acc|accexif`, `perf=<groups or ids>`,
  `spin=0|1`) to `/sdcard/Android/data/com.example.ocr_spike/files/` (chmod 666);
  output lines are `PERFBENCH <id> <i>/<n> <json chunk>` and `OCRBENCH {json}`.
- Phone: `flutter build apk --release --target-platform android-arm64 --dart-define=DEVICE=phone`.
