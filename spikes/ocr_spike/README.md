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

## Phase 1.6b/c (phone studies, safe harness)

- Perf page buttons: A (UI load A/B), B (provider x threads, two passes), C
  (provider accuracy), D (best), F (paired A/B), G (language packs). Each cell
  is saved to a log before and after it runs; after a crash the page shows the
  cell where it stopped and the Android exit reason, and Resume continues.
- `lib/bench/sample_guard.dart` skips a full-size decode above 50 MP (header read
  only); `--dart-define=UNSAFE=true` switches the guard off (reproduction only,
  never on a 200 MP image on the 2 GB emulator).
- Emulator modes in `autorun.txt`: `study`, `grid`, `prov`, `best`, `paired`,
  `langs`, `sample` (with `sample=<file>` and `perf=<ids>`), `pause=<s>`.
