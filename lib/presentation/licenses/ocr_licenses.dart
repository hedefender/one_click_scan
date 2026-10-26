import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the licences that Flutter does not collect by itself to the licence
/// screen (`showLicensePage`). The Dart packages (flutter_onnxruntime, image,
/// crypto and the rest) are listed by Flutter automatically; what is added
/// here is what has no pub package: the OCR model files and the native ONNX
/// Runtime library. Texts are the licence files of the projects, kept in
/// `assets/licenses/`. The same list is in `docs/THIRD_PARTY_NOTICES.md`.
void registerOcrLicenses({
  Future<String> Function(String assetPath)? loadAsset,
}) {
  final loadText = loadAsset ?? rootBundle.loadString;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['PaddleOCR PP-OCRv5 models'],
      'Text detection and recognition models PP-OCRv5 (mobile) of PaddleOCR, '
      'PaddlePaddle Authors, licensed under the Apache License 2.0. The ONNX '
      'conversions bundled with the app were made by third parties '
      '(monkt/paddleocr-onnx and ilaylow/PP_OCRv5_mobile_onnx on Hugging '
      'Face, also Apache-2.0).\n\n'
      '${await loadText('assets/licenses/paddleocr_LICENSE.txt')}',
    );
    yield LicenseEntryWithLineBreaks(
      const ['ONNX Runtime'],
      'ONNX Runtime, Microsoft Corporation, MIT License.\n\n'
      '${await loadText('assets/licenses/onnxruntime_LICENSE.txt')}',
    );
    yield LicenseEntryWithLineBreaks(
      const ['Noto Sans'],
      'Noto Sans Regular, The Noto Project Authors, licensed under the SIL '
      'Open Font License 1.1. The app embeds the few letters it needs of this '
      'font in the invisible text of the PDF.\n\n'
      '${await loadText('assets/licenses/notosans_OFL.txt')}',
    );
  });
}
