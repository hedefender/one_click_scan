import '../../domain/entities/stored_scan.dart';
import '../../domain/usecases/recognize_pages.dart';

/// What the result screen of a scan needs: what was stored, and the
/// background reading of its pages (null when there is none).
class ScanResultArgs {
  const ScanResultArgs({required this.result, this.ocr});

  final StoredScan result;
  final OcrSession? ocr;
}
