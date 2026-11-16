/// Keeps the screen on while the app works for the user without a touch: the
/// reading of the pages, the PDF and the send of the e-mail can take a minute
/// or more (A1-004). The owner of the work switches it on and ALWAYS off again,
/// whatever the end: success, error, cancel, discard, or leaving the screen.
abstract interface class ScreenAwake {
  /// `true` keeps the screen on, `false` gives the system its normal timeout
  /// back. Never throws; a platform without it does nothing.
  Future<void> keepOn(bool on);
}
