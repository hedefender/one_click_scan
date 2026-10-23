import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';

import 'ocr_engine.dart';
import 'paddle/native_decode.dart';
import 'paddle/paddle_config.dart';
import 'paddle/paddle_models.dart';
import 'paddle/paddle_pixels.dart';
import 'paddle_engine.dart';

/// [PaddleEngine] running in a long-lived background isolate: decoding,
/// pixel maths, post-processing and the plugin calls all happen off the UI
/// isolate. With [DecodeMode.native] the decode stays in the root isolate
/// (`dart:ui` is not available elsewhere) and the pixels are handed over.
class IsolatePaddleEngine implements SpikeOcrEngine {
  IsolatePaddleEngine(this.recKey, this.config);

  final String recKey;
  final PaddleConfig config;

  Isolate? _isolate;
  SendPort? _worker;
  ReceivePort? _replies;
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  Map<String, int> _loadUs = const {};

  /// Same meaning as [PaddleEngine.lastLoadUs].
  Map<String, int> get lastLoadUs => _loadUs;

  @override
  String get id => 'paddle_${recKey}_isolate';

  @override
  String get languages => recKey;

  Future<void> _start() async {
    if (_worker != null) return;
    final files = await PaddleModels.resolve(recKey, argmax: config.recArgmax);
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((Object? m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is List) {
        _pending.remove(m[0] as int)?.complete(m[1]);
      }
    });
    _replies = replies;
    _isolate = await Isolate.spawn(_entry, <Object?>[
      replies.sendPort,
      RootIsolateToken.instance,
      recKey,
      config.toMap(),
      files.toMap(),
    ]);
    _worker = await ready.future;
  }

  Future<Object?> _call(String op, Object? data) {
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _worker!.send(<Object?>[id, op, data]);
    return c.future;
  }

  @override
  Future<void> prepare() async {
    final t = StageTimer();
    await _start();
    t.lap('spawn');
    final m = await _call('prepare', null) as Map;
    final load = {for (final e in m.entries) e.key as String: e.value as int};
    if (load.isNotEmpty) _loadUs = {...load, 'spawn': t.micros['spawn']!};
  }

  @override
  Future<OcrResult> recognize(String imagePath) async {
    final wall = StageTimer();
    await prepare();
    wall.skip();
    final main = StageTimer();
    Object? data;
    String op;
    if (config.decode == DecodeMode.native) {
      op = 'pixels';
      try {
        final px = await decodeNative(imagePath, config.maxSide, main);
        data = [
          TransferableTypedData.fromList([px.data]),
          px.w,
          px.h,
          px.stride,
        ];
        main.lap('handover');
      } catch (e) {
        return OcrResult(text: '', elapsedMs: 0, error: '${e.runtimeType}');
      }
    } else {
      op = 'path';
      data = imagePath;
    }
    final reply = await _call(op, data) as Map;
    final workerUs = reply['us'] as int;
    final breakdown = <String, int>{
      for (final e in (reply['breakdown'] as Map).entries)
        e.key as String: e.value as int,
    };
    for (final e in main.micros.entries) {
      breakdown['us_${e.key}'] = (breakdown['us_${e.key}'] ?? 0) + e.value;
    }
    final wallUs = wall.totalUs;
    breakdown['us_total'] = wallUs;
    breakdown['us_ipc'] =
        wallUs - workerUs - main.micros.values.fold<int>(0, (a, b) => a + b);
    final flat = reply['lines'] as List;
    return OcrResult(
      text: reply['text'] as String,
      elapsedMs: (wallUs / 1000).round(),
      error: reply['error'] as String?,
      confidence: reply['conf'] as double?,
      lines: [
        for (var i = 0; i < flat.length; i += 6)
          OcrLine(
            flat[i] as String,
            Rect.fromLTRB(
              flat[i + 1] as double,
              flat[i + 2] as double,
              flat[i + 3] as double,
              flat[i + 4] as double,
            ),
            confidence: flat[i + 5] as double,
          ),
      ],
      breakdown: breakdown,
    );
  }

  /// Changes the recognition batch size for the next runs (sessions stay).
  Future<void> setRecBatch(int n) async {
    await _call('batch', n);
  }

  /// Closes the sessions inside the worker (next [prepare] loads again).
  Future<void> release() async {
    if (_worker == null) return;
    await _call('release', null);
    _loadUs = const {};
  }

  @override
  Future<void> dispose() async {
    // The sessions live in the native plugin: close them before the isolate
    // that owns the handles goes away.
    if (_worker != null) await _call('release', null);
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    _isolate = null;
    _worker = null;
    _replies = null;
  }
}

Future<void> _entry(List<Object?> args) async {
  final reply = args[0]! as SendPort;
  final token = args[1] as RootIsolateToken?;
  if (token != null) BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final engine = PaddleEngine(
    args[2]! as String,
    config: PaddleConfig.fromMap(args[3]! as Map),
    files: PaddleModelFiles.fromMap(args[4]! as Map),
  );
  final port = ReceivePort();
  reply.send(port.sendPort);
  await for (final msg in port) {
    final m = msg as List;
    final id = m[0] as int;
    try {
      switch (m[1] as String) {
        case 'prepare':
          await engine.prepare();
          reply.send([id, Map<String, int>.of(engine.lastLoadUs)]);
          engine.lastLoadUs = const {};
        case 'batch':
          engine.config = engine.config.copyWith(recBatch: m[2] as int);
          reply.send([id, null]);
        case 'release':
          await PaddleEngine.releaseAll();
          reply.send([id, null]);
        case 'path':
          reply.send([id, _encode(await engine.recognize(m[2] as String))]);
        case 'pixels':
          final d = m[2] as List;
          final t = StageTimer();
          final bytes = (d[0] as TransferableTypedData)
              .materialize()
              .asUint8List();
          t.lap('materialize');
          final result = await engine.recognizePixels(
            Pixels(bytes, d[1] as int, d[2] as int, d[3] as int),
            t,
          );
          reply.send([id, _encode(result)]);
      }
    } catch (e) {
      reply.send([
        id,
        {
          'text': '',
          'us': 0,
          'error': '${e.runtimeType}',
          'conf': null,
          'lines': <Object?>[],
          'breakdown': <String, int>{},
        },
      ]);
    }
  }
}

Map<String, Object?> _encode(OcrResult r) => {
  'text': r.text,
  'us': r.breakdown['us_total'] ?? r.elapsedMs * 1000,
  'error': r.error,
  'conf': r.confidence,
  'breakdown': Map<String, int>.of(r.breakdown),
  'lines': [
    for (final l in r.lines) ...[
      l.text,
      l.box.left,
      l.box.top,
      l.box.right,
      l.box.bottom,
      l.confidence ?? 0.0,
    ],
  ],
};
