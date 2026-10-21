import 'dart:async';

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_data_source.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._local);

  final SettingsLocalDataSource _local;
  final StreamController<AppSettings> _changes =
      StreamController<AppSettings>.broadcast();

  @override
  Future<AppSettings> load() async => _local.read();

  @override
  Future<void> save(AppSettings settings) async {
    await _local.write(settings);
    _changes.add(settings);
  }

  @override
  Stream<AppSettings> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();
}
