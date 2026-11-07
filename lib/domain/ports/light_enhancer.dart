import '../ocr/ocr_cancellation.dart';

/// Removes shadow and uneven light from a picture of a page (`flat`, ADR-030).
///
/// The implementation runs in a background isolate and never throws. It writes
/// a JPEG to [target] and returns true, or returns false and leaves no file
/// there. Only ever started by an action of the user.
abstract interface class LightEnhancer {
  Future<bool> enhance({
    required String source,
    required String target,
    required int jpegQuality,
    required Duration timeout,
    OcrCancellation? cancellation,
  });
}
