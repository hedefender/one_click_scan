enum AppLanguage {
  el('el'),
  en('en');

  const AppLanguage(this.code);

  final String code;

  static AppLanguage? fromCode(String? code) {
    if (code == null) return null;
    for (final language in AppLanguage.values) {
      if (language.code == code) return language;
    }
    return null;
  }
}
