/// Immutable application configuration.
///
/// Framework-agnostic on purpose: `core/` must not depend on `domain/`,
/// so the default language is carried as a plain language code.
class AppConfig {
  const AppConfig({
    required this.appName,
    required this.settingsSchemaVersion,
    required this.defaultLanguageCode,
  });

  /// Languages the UI is translated to. Anything else falls back to English.
  static const supportedLanguageCodes = <String>['el', 'en'];

  /// Picks `el` when the device language is Greek, `en` otherwise.
  factory AppConfig.forDeviceLanguage(String deviceLanguageCode) {
    return AppConfig(
      appName: 'One Click Scan',
      settingsSchemaVersion: 1,
      defaultLanguageCode: deviceLanguageCode == 'el' ? 'el' : 'en',
    );
  }

  final String appName;

  /// Version of the persisted settings layout (not the JSON scan contract).
  final int settingsSchemaVersion;

  final String defaultLanguageCode;
}
