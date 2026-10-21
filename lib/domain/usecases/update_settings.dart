import '../entities/app_settings.dart';
import '../repositories/settings_repository.dart';

/// Read-modify-write on the persisted settings.
class UpdateSettings {
  const UpdateSettings(this._repository);

  final SettingsRepository _repository;

  Future<AppSettings> call(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final current = await _repository.load();
    final updated = transform(current);
    await _repository.save(updated);
    return updated;
  }
}
