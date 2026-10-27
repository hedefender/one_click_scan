/// Opens a web page in the browser of the user. Only for the guide of the
/// provider, and only when the user taps the button; it uses no network of the
/// app (the browser does).
abstract interface class LinkOpener {
  /// True when a browser was started. Never throws.
  Future<bool> open(String url);
}
