import 'package:flutter/foundation.dart';

import 'app_logger_interface.dart';

// The interface lives in its own file without Flutter (A1-016); this export
// keeps every `import '.../app_logger.dart'` outside `domain/` working.
export 'app_logger_interface.dart';

/// Prints through `debugPrint`. See the privacy rule of [AppLogger].
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
