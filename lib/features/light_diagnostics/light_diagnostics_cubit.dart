import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/lighting/flash_mode.dart';
import '../../domain/lighting/light_metric.dart';
import '../../domain/ports/light_meter.dart';
import '../../services/camera/camera_service.dart';
import '../../services/scan_files/scan_temp_store.dart';

class LightDiagnosticsState extends Equatable {
  const LightDiagnosticsState({
    this.ready = false,
    this.failed = false,
    this.live,
    this.lastShot,
    this.flashMode = FlashMode.off,
    this.hasFlash = false,
    this.taking = false,
  });

  final bool ready;
  final bool failed;

  /// The metric of the latest preview sample.
  final LightMetric? live;

  /// The metric of the last shot taken on this screen.
  final LightMetric? lastShot;
  final FlashMode flashMode;
  final bool hasFlash;
  final bool taking;

  LightDiagnosticsState copyWith({
    bool? ready,
    bool? failed,
    LightMetric? live,
    LightMetric? lastShot,
    FlashMode? flashMode,
    bool? hasFlash,
    bool? taking,
  }) => LightDiagnosticsState(
    ready: ready ?? this.ready,
    failed: failed ?? this.failed,
    live: live ?? this.live,
    lastShot: lastShot ?? this.lastShot,
    flashMode: flashMode ?? this.flashMode,
    hasFlash: hasFlash ?? this.hasFlash,
    taking: taking ?? this.taking,
  );

  @override
  List<Object?> get props => [
    ready,
    failed,
    live,
    lastShot,
    flashMode,
    hasFlash,
    taking,
  ];
}

/// The hidden screen that shows the light numbers (ADR-030), so the threshold
/// can be calibrated on the phone. It stores no picture and no text: the shot
/// is measured and deleted at once, only numbers stay on the screen.
class LightDiagnosticsCubit extends Cubit<LightDiagnosticsState> {
  LightDiagnosticsCubit({
    required this._camera,
    required this._meter,
    required this._tempStore,
  }) : super(const LightDiagnosticsState());

  final CameraService _camera;
  final LightMeter _meter;
  final ScanTempStore _tempStore;
  StreamSubscription<LightMetric>? _subscription;

  Future<void> start() async {
    final result = await _camera.open();
    if (isClosed) {
      await _camera.close();
      return;
    }
    if (result != CameraOpenResult.ready) {
      emit(state.copyWith(failed: true));
      return;
    }
    _subscription = _camera.lightSamples.listen((metric) {
      if (!isClosed) emit(state.copyWith(live: metric));
    });
    _camera.startLightAnalysis();
    emit(state.copyWith(ready: true, hasFlash: _camera.hasFlash));
  }

  /// Flash for the comparison with and without it. Not remembered.
  Future<void> cycleFlash() async {
    if (!state.hasFlash) return;
    final next = state.flashMode.next;
    await _camera.setFlashMode(next);
    emit(state.copyWith(flashMode: next));
  }

  Future<void> take() async {
    if (!state.ready || state.taking) return;
    emit(state.copyWith(taking: true));
    String? path;
    try {
      final page = await _camera.capture(order: 1);
      path = page.path;
      final metric = await _meter.measureFile(path);
      if (!isClosed && metric != null) {
        emit(state.copyWith(lastShot: metric));
      }
    } catch (_) {
      // A failed shot only shows no new number.
    } finally {
      if (path != null) await _tempStore.delete([path]);
      if (!isClosed) emit(state.copyWith(taking: false));
    }
  }

  @override
  Future<void> close() async {
    unawaited(_subscription?.cancel());
    _camera.stopLightAnalysis();
    await _camera.close();
    return super.close();
  }
}
