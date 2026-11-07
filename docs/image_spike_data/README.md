# Raw data of the Phase 6.0 image spike

Synthetic pictures only (no personal data). Numbers and Markdown reports; the
OCR text is never logged. See `docs/IMAGE_SPIKE_RESULTS.md` for the analysis.

| File | What it is |
|---|---|
| `detect_a3_pc_fullres_report.md`, `detect_a3_pc_fullres.csv` | Detector A3 on the PC (debug JIT) at 1536 x 2048, 77 pictures (2026-10-30). |
| `opencv_feasibility_build.txt` | The first build with `opencv_dart` (time and APK size). |
| `detect_a3_vs_small_area_pc_halfres_report.md`, `.csv` | A3 and A3 with the lower area bound (small pages) on the PC at 768 x 1024, 77 pictures. |

Two earlier OCR runs ended without results and are not kept: the first was killed by memory (all 77 pictures loaded at once on a 2 GB emulator), the second crashed with SIGABRT inside ONNX Runtime because R8 removed its Java classes (`JNI DETECTED ERROR IN APPLICATION: java_class == null`); the spike needed the same keep rule as the main app (`android/app/proguard-rules.pro`).

The raw run logs of the emulator runs (`*.log`) are not kept in the repository; their numbers are in the tables of `docs/IMAGE_SPIKE_RESULTS.md`.
