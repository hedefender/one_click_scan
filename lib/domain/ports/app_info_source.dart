/// Version of the app and of the phone, as shown in About and written in the
/// feedback e-mail. Numbers only: nothing about the user.
class AppInfo {
  const AppInfo({
    required this.versionName,
    required this.buildNumber,
    required this.androidRelease,
  });

  /// `0.1.0`
  final String versionName;

  /// `1`
  final String buildNumber;

  /// `14`; empty when unknown.
  final String androidRelease;

  /// `0.1.0 (1)`
  String get versionLabel => '$versionName ($buildNumber)';
}

abstract interface class AppInfoSource {
  /// Never throws; null when the platform cannot say.
  Future<AppInfo?> read();
}
