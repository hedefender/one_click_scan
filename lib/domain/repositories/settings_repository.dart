import '../entities/app_settings.dart';

abstract interface class SettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);

  /// Emits every time [save] completes.
  Stream<AppSettings> get changes;
}
