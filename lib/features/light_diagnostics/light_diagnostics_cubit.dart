import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/lighting/flash_mode.dart';
import '../../domain/lighting/light_metric.dart';
import '../../domain/lighting/lighting_config.dart';
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
    this.torchLit = false,
    this.litFor,
    this.sampleAfterTorch = false,
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

  /// The torch is really lit (flash On).
  final bool torchLit;

  /// Time since the torch was last lit; null while it is out.
  final Duration? litFor;

  /// The latest live sample was taken after the torch was lit and settled.
  final bool sampleAfterTorch;

  LightDiagnosticsState copyWith({
    bool? ready,
    bool? failed,
    LightMetric? live,
    LightMetric? lastShot,
    FlashMode? flashMode,
    bool? hasFlash,
    bool? taking,
    bool? torchLit,
    Duration? litFor,
    bool clearLitFor = false,
    bool? sampleAfterTorch,
  }) => LightDiagnosticsState(
    ready: ready ?? this.ready,
    failed: failed ?? this.failed,
    live: live ?? this.live,
    lastShot: lastShot ?? this.lastShot,
    flashMode: flashMode ?? this.flashMode,
    hasFlash: hasFlash ?? this.hasFlash,
    taking: taking ?? this.taking,
    torchLit: torchLit ?? this.torchLit,
    litFor: clearLitFor ? null : litFor ?? this.litFor,
    sampleAfterTorch: sampleAfterTorch ?? this.sampleAfterTorch,
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
    torchLit,
    litFor,
    sampleAfterTorch,
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
    DateTime Function()? now,
    this._settleDelay = LightingConfig.torchSettleDelay,
  }) : _now = now ?? DateTime.now,
       super(const LightDiagnosticsState());

  final CameraService _camera;
  final LightMeter _meter;
  final ScanTempStore _tempStore;
  final DateTime Function() _now;
  final Duration _settleDelay;
  StreamSubscription<LightMetric>? _subscription;
  DateTime? _litAt;
  Timer? _ticker;

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
      if (isClosed) return;
      final litAt = _litAt;
      final after = litAt != null && _now().difference(litAt) >= _settleDelay;
      emit(state.copyWith(live: metric, sampleAfterTorch: after));
    });
    _camera.startLightAnalysis();
    emit(state.copyWith(ready: true, hasFlash: _camera.hasFlash));
  }

  /// Flash for the comparison with and without it. Not remembered.
  Future<void> cycleFlash() async {
    if (!state.hasFlash) return;
    final next = state.flashMode.next;
    await _camera.setFlashMode(next);
    // On is the torch (ADR-031): lit here, for the comparison with and
    // without it; any other mode has put it out.
    if (next == FlashMode.on) await _camera.setTorchLit(true);
    emit(state.copyWith(flashMode: next));
    _noteTorch();
  }

  /// The screen lost the focus: the torch goes out at once.
  Future<void> onInactive() async {
    await _camera.setTorchLit(false);
    _noteTorch();
  }

  /// The screen is back: the torch is lit again when the choice is still On.
  Future<void> onResumed() async {
    if (state.flashMode == FlashMode.on) await _camera.setTorchLit(true);
    _noteTorch();
  }

  void _noteTorch() {
    final lit = _camera.torchLit;
    if (lit == state.torchLit || isClosed) return;
    if (lit) {
      _litAt = _now();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        final at = _litAt;
        if (at != null && !isClosed) {
          emit(state.copyWith(litFor: _now().difference(at)));
        }
      });
      emit(
        state.copyWith(
          torchLit: true,
          litFor: Duration.zero,
          sampleAfterTorch: false,
        ),
      );
    } else {
      _litAt = null;
      _ticker?.cancel();
      _ticker = null;
      emit(
        state.copyWith(
          torchLit: false,
          clearLitFor: true,
          sampleAfterTorch: false,
        ),
      );
    }
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
    _ticker?.cancel();
    await _camera.setTorchLit(false);
    unawaited(_subscription?.cancel());
    _camera.stopLightAnalysis();
    await _camera.close();
    return super.close();
  }
}
