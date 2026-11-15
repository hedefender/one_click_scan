/// Minimal logging abstraction. Pure Dart, with no import of Flutter, so the
/// domain layer can use it (A1-016). The implementation that prints is
/// `DebugAppLogger` in `app_logger.dart`.
///
/// PRIVACY RULE: never log OCR text, e-mail addresses, file names that may
/// contain personal data, or any other user content. Log events and error
/// types only.
abstract interface class AppLogger {
  void debug(String message);

  void error(String message, [Object? error, StackTrace? stackTrace]);
}
