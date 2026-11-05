# Raw data of the Phase 6.0 image spike

Synthetic pictures only (no personal data). Numbers and Markdown reports; the
OCR text is never logged. See `docs/IMAGE_SPIKE_RESULTS.md` for the analysis.

| File | What it is |
|---|---|
| `detect_a3_pc_fullres_report.md`, `detect_a3_pc_fullres.csv` | Detector A3 on the PC (debug JIT) at 1536 x 2048, 77 pictures (2026-10-30). |
| `detect_emulator_halfres_run1_a1poly_a3.log` | First emulator run (release, x86_64, 768 x 1024): A3 and A1 with approxPolyDP. `IMGEVAL csv` lines are one picture each, `IMGEVAL report` lines the Markdown. |
| `detect_emulator_halfres_3detectors.log` | Second run: A3, A1 approxPolyDP and A1 with the enclosing quad. |
| `opencv_feasibility_build.txt` | The first build with `opencv_dart` (time and APK size). |
| `detect_a3_vs_small_area_pc_halfres_report.md`, `.csv` | A3 and A3 with the lower area bound (small pages) on the PC at 768 x 1024, 77 pictures. |
| `ocr_run3_77scenes_wordcount_check.log` | OCR gain run 3 (emulator, release): 77 scenes, safety check by word count only. First run that worked after the R8 fix. |
| `ocr_run4_77scenes_coverage_check_small_area.log` | Run 4: adds the frame-text coverage check and the small-area pipeline A3small. |
| `ocr_run5_final_83scenes.log` | Run 5 (final): 83 scenes, adds the 6 tilted two-column receipts and the label-value pairing. `OCREVAL csv` lines (one per page and condition), `OCREVAL detreport` (detection at 1536 x 2048), `OCREVAL report` (Markdown). |

Two earlier OCR runs ended without results and are not kept: the first was killed by memory (all 77 pictures loaded at once on a 2 GB emulator), the second crashed with SIGABRT inside ONNX Runtime because R8 removed its Java classes (`JNI DETECTED ERROR IN APPLICATION: java_class == null`); the spike needed the same keep rule as the main app (`android/app/proguard-rules.pro`).
