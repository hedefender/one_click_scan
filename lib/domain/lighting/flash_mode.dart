/// Flash of the camera screen (ADR-030).
enum FlashMode {
  off,
  auto,

  /// Fires on every shot. For the current use only: it is never stored as On.
  on;

  /// What is written to the settings. **Only Off and Auto are remembered.**
  /// On is stored as Auto, so the next start opens in Auto (the battery is not
  /// spent by a flash the user forgot) and a full On is always a new choice.
  String get storedName => this == on ? auto.name : name;

  /// Reads a stored value. Missing or unknown: Off (the default). A stored
  /// "on" (never written by this version) also becomes Auto.
  static FlashMode fromStored(String? value) {
    return switch (value) {
      'auto' || 'on' => FlashMode.auto,
      _ => FlashMode.off,
    };
  }

  /// Off -> Auto -> On -> Off, the order of the button.
  FlashMode get next => switch (this) {
    off => auto,
    auto => on,
    on => off,
  };
}
