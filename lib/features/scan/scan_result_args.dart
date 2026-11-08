import '../../domain/entities/stored_scan.dart';
import '../../domain/usecases/recognize_pages.dart';

/// What the result screen of a scan needs: what was stored, and the
/// background reading of its pages (null when there is none).
class ScanResultArgs {
  const ScanResultArgs({
    required this.result,
    this.ocr,
    this.darkPages = const <String>[],
    this.darkNeedsRetake = false,
  });

  final StoredScan result;
  final OcrSession? ocr;

  /// Keys (paths of the shots) of the pages measured dark that have no
  /// decision yet: the preview offers the light correction for them
  /// (ADR-030). Empty in One Click, where the decision is made before.
  final List<String> darkPages;

  /// One of [darkPages] is so dark that the correction is not expected to
  /// help: the banner advises a retake first (ADR-031).
  final bool darkNeedsRetake;
}
