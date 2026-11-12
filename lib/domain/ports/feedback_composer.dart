/// Opens the e-mail app with a message to write (no attachment). The user
/// presses send there; the app never sends feedback by itself.
abstract interface class FeedbackComposer {
  /// True when an e-mail app was opened. Never throws.
  Future<bool> compose({
    required String to,
    required String subject,
    required String body,
  });
}
