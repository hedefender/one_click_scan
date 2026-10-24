import 'package:flutter/widgets.dart';

/// Widget keys used by widget and integration tests.
abstract final class OcrKeys {
  static const status = Key('ocr.status');
  static const progressBar = Key('ocr.progressBar');
  static const summary = Key('ocr.summary');
  static const lines = Key('ocr.lines');
  static const copy = Key('ocr.copy');
  static const showBoxes = Key('ocr.showBoxes');
  static const boxesImage = Key('ocr.boxesImage');
  static const previousPage = Key('ocr.previousPage');
  static const nextPage = Key('ocr.nextPage');
  static const pageLabel = Key('ocr.pageLabel');
  static const noText = Key('ocr.noText');
  static const failure = Key('ocr.failure');

  static Key line(int index) => Key('ocr.line.$index');
}
