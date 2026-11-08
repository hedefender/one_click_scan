/// Remembers that the user has seen the hint that opens the first time Multi
/// Page is chosen (Phase 6.3).
abstract interface class MultiPageHintStore {
  /// The hint was shown before.
  bool get seen;

  Future<void> markSeen();
}
