/// Where the feedback e-mail of About goes.
abstract final class FeedbackConfig {
  /// The address that receives the feedback. Empty on purpose until the owner
  /// fills it in: while it is empty, the "Send feedback" button is not shown.
  static const recipient = '';
}
