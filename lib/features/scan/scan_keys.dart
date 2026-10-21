import 'package:flutter/widgets.dart';

/// Widget keys used by widget and integration tests.
abstract final class ScanKeys {
  static const modeSelector = Key('scan.mode');
  static const preview = Key('scan.preview');
  static const capture = Key('scan.capture');
  static const done = Key('scan.done');
  static const deleteLast = Key('scan.deleteLast');
  static const thumbnails = Key('scan.thumbnails');
  static const saving = Key('scan.saving');
  static const retryCamera = Key('scan.retryCamera');
  static const openAppSettings = Key('scan.openAppSettings');
  static const retrySave = Key('scan.retrySave');
  static const folderOpenSettings = Key('scan.folderOpenSettings');
  static const captureFailed = Key('scan.captureFailed');
  static const dialogDiscard = Key('scan.dialog.discard');
  static const dialogStay = Key('scan.dialog.stay');
  static const resultList = Key('scan.result.list');
  static const resultBack = Key('scan.result.back');

  static Key resultFile(String fileName) => Key('scan.result.file.$fileName');
}
