import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';

/// App-wide, read-only view of the persisted settings.
///
/// Writers (wizard, future settings screen) go through `UpdateSettings`;
/// this cubit simply mirrors every saved change so the whole UI (for example
/// the language) reacts immediately.
class SettingsCubit extends Cubit<AppSettings> {
  SettingsCubit(SettingsRepository repository, AppSettings initial)
    : super(initial) {
    _subscription = repository.changes.listen(emit);
  }

  late final StreamSubscription<AppSettings> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
