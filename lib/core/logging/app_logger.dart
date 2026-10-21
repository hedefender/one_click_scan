import 'package:flutter/foundation.dart';

/// Minimal logging abstraction.
///
/// PRIVACY RULE: never log OCR text, e-mail addresses, file names that may
/// contain personal data, or any other user content. Log events and error
/// types only.
abstract interface class AppLogger {
  void debug(String message);

  void error(String message, [Object? error, StackTrace? stackTrace]);
}

class DebugAppLogger implements AppLogger {
  const DebugAppLogger();

  @override
  void debug(String message) => debugPrint('[debug] $message');

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint(
      '[error] $message${error != null ? ' (${error.runtimeType})' : ''}',
    );
  }
}
