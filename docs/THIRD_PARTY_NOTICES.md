# Third-party notices

Phase 2 adds text recognition (OCR) to the app. This file lists what comes from
others and under which licence. The same texts are shown in the app: Settings,
"Open-source licences" (Flutter's licence page; the entries for the OCR models
and for ONNX Runtime are added by `lib/presentation/licenses/ocr_licenses.dart`
from `assets/licenses/`).

Flutter collects the licence files of all Dart packages in `pubspec.yaml`
automatically, so the packages below are also on that screen. They are listed
here to make the OCR part of the picture complete.

## OCR models (bundled in the APK, not in git)

| Item | What | Licence | Source |
|---|---|---|---|
| PP-OCRv5 mobile detection | text detection model | Apache-2.0 | PaddleOCR, PaddlePaddle Authors; ONNX conversion by `ilaylow/PP_OCRv5_mobile_onnx` (Hugging Face, Apache-2.0) |
| PP-OCRv5 `el` recognition (greek pack) | Greek + English recognition model and dictionary | Apache-2.0 | PaddleOCR; ONNX conversion by `monkt/paddleocr-onnx` (Hugging Face, Apache-2.0) |
| PP-OCRv5 `latin` recognition (latin pack) | Latin-script recognition model and dictionary | Apache-2.0 | PaddleOCR; ONNX conversion by `monkt/paddleocr-onnx` |

- The Apache-2.0 text is `assets/licenses/paddleocr_LICENSE.txt` (the licence
  file of the PaddleOCR repository, copyright 2016 PaddlePaddle Authors).
- The files are pinned by commit and checked by SHA-256 (`assets/ocr/manifest.json`,
  `tool/fetch_ocr_models.sh`, the Gradle task `verifyOcrModels`, and again each
  time the engine loads a model).
- **Open item (before any public release):** the ONNX files are third-party
  conversions. They will be rebuilt from the official PaddlePaddle weights with
  `paddle2onnx`, and hosted on GitHub Releases of this project, so the chain
  has no third-party link. Until then the mirrors above are the provenance.
  See `OCR_LANGUAGE_PACKS.md` section 5.

## Libraries

| Item | Version | Licence | Used for |
|---|---|---|---|
| ONNX Runtime (Android, `com.microsoft.onnxruntime:onnxruntime-android`) | 1.28.0 | MIT, Microsoft Corporation | runs the models (native library, about 28.7 MB per ABI) |
| `flutter_onnxruntime` | 1.9.0 | MIT, MASIC AI | Flutter bridge to ONNX Runtime |
| `image` | 4.12.0 | MIT, Brendan Duncan | decoding and encoding the small working copies, in a background isolate |
| `crypto` | 3.0.7 | BSD-3-Clause, Dart project authors | SHA-256 of the model files |

The MIT text of ONNX Runtime is `assets/licenses/onnxruntime_LICENSE.txt`.

Packages of the earlier phases (`camera`, `gal`, `flutter_bloc`, `get_it`,
`go_router`, `shared_preferences`, `path_provider`, `equatable`) keep their own
licences; they appear on Flutter's licence page.

## What does not come from others

The pixel pre- and post-processing around the two networks (resize, detection
post-processing, crops, CTC decoding) is written for this project in Dart
(`lib/services/ocr/paddle/`). The tests use invented documents only.
