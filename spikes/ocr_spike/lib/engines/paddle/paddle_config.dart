import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Where the image is decoded.
enum DecodeMode {
  /// `package:image` in pure Dart (the Phase 1.5 behaviour).
  dart,

  /// Flutter's native codec (`dart:ui`), optionally down-scaled while decoding.
  /// Only available in the root isolate.
  native,
}

/// Every knob of the Phase 1.6 experiments. The defaults are the Phase 1.5
/// pipeline, so `const PaddleConfig()` is the baseline.
class PaddleConfig {
  const PaddleConfig({
    this.threads = 4,
    this.providers,
    this.allowSpinning,
    this.detSide = 960,
    this.recBatch = 1,
    this.fastPixels = false,
    this.decode = DecodeMode.dart,
    this.maxSide = 0,
    this.isolate = false,
    this.recArgmax = false,
  });

  /// ONNX Runtime intra-op threads.
  final int threads;

  /// Execution providers in order of preference; null = the plugin default (CPU).
  final List<OrtProvider>? providers;

  /// `session.intra_op.allow_spinning`; null = ONNX Runtime default.
  final bool? allowSpinning;

  /// Longest side of the detection input (multiple of 32 after rounding).
  final int detSide;

  /// Recognition crops per `run` call (sorted by width when above 1).
  final int recBatch;

  /// Typed-list pixel loops, no per-pixel allocation (same maths as the
  /// baseline, so the output must match up to float rounding).
  final bool fastPixels;

  final DecodeMode decode;

  /// Longest side kept when decoding natively; 0 = full resolution.
  final int maxSide;

  /// Run the whole engine in a background isolate.
  final bool isolate;

  /// Use the recognition model variant with ArgMax/ReduceMax inside the graph
  /// (`rec_<k>_am.onnx`): `[B,T]` indices and probabilities come back instead
  /// of `[B,T,C]` probabilities.
  final bool recArgmax;

  /// Key of what a loaded session depends on.
  String get sessionKey =>
      'th$threads|${providers?.map((p) => p.name).join('+') ?? 'default'}'
      '|spin${allowSpinning ?? '-'}';

  PaddleConfig copyWith({
    int? threads,
    List<OrtProvider>? providers,
    bool? allowSpinning,
    int? detSide,
    int? recBatch,
    bool? fastPixels,
    DecodeMode? decode,
    int? maxSide,
    bool? isolate,
    bool? recArgmax,
  }) => PaddleConfig(
    threads: threads ?? this.threads,
    providers: providers ?? this.providers,
    allowSpinning: allowSpinning ?? this.allowSpinning,
    detSide: detSide ?? this.detSide,
    recBatch: recBatch ?? this.recBatch,
    fastPixels: fastPixels ?? this.fastPixels,
    decode: decode ?? this.decode,
    maxSide: maxSide ?? this.maxSide,
    isolate: isolate ?? this.isolate,
    recArgmax: recArgmax ?? this.recArgmax,
  );

  /// Plain map for the worker isolate.
  Map<String, Object?> toMap() => {
    'threads': threads,
    'providers': providers?.map((p) => p.name).toList(),
    'spin': allowSpinning,
    'detSide': detSide,
    'recBatch': recBatch,
    'fast': fastPixels,
    'decode': decode.name,
    'maxSide': maxSide,
    'isolate': isolate,
    'argmax': recArgmax,
  };

  factory PaddleConfig.fromMap(Map<Object?, Object?> m) {
    final names = OrtProvider.values.asNameMap();
    return PaddleConfig(
      threads: m['threads']! as int,
      providers: (m['providers'] as List?)
          ?.map((n) => names[n]!)
          .toList(growable: false),
      allowSpinning: m['spin'] as bool?,
      detSide: m['detSide']! as int,
      recBatch: m['recBatch']! as int,
      fastPixels: m['fast']! as bool,
      decode: DecodeMode.values.byName(m['decode']! as String),
      maxSide: m['maxSide']! as int,
      isolate: m['isolate']! as bool,
      recArgmax: m['argmax']! as bool,
    );
  }
}

/// Resolved model files, so a background isolate never needs `rootBundle`.
class PaddleModelFiles {
  const PaddleModelFiles({
    required this.detPath,
    required this.recPath,
    required this.dictText,
  });
  final String detPath, recPath, dictText;

  Map<String, Object?> toMap() => {
    'det': detPath,
    'rec': recPath,
    'dict': dictText,
  };

  factory PaddleModelFiles.fromMap(Map<Object?, Object?> m) => PaddleModelFiles(
    detPath: m['det']! as String,
    recPath: m['rec']! as String,
    dictText: m['dict']! as String,
  );
}

/// Sums wall-clock time per named stage. `lap` charges the time since the
/// previous lap, so consecutive laps cover the whole run without gaps.
class StageTimer {
  final _sw = Stopwatch()..start();
  final Map<String, int> _us = {};
  int _last = 0;

  void lap(String stage) {
    final now = _sw.elapsedMicroseconds;
    _us[stage] = (_us[stage] ?? 0) + (now - _last);
    _last = now;
  }

  /// Restarts the lap clock without charging anyone (after waiting on others).
  void skip() => _last = _sw.elapsedMicroseconds;

  void add(String stage, int us) => _us[stage] = (_us[stage] ?? 0) + us;

  int get totalUs => _sw.elapsedMicroseconds;

  Map<String, int> get micros => Map.unmodifiable(_us);
}
