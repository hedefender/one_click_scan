import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/ocr_line.dart';
import '../../domain/entities/ocr_outcome.dart';
import '../../domain/entities/ocr_progress.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/entities/upright_image.dart';
import '../../domain/ocr/ocr_cancellation.dart';
import '../../domain/ocr/ocr_config.dart';
import '../../domain/ocr/ocr_language_pack_registry.dart';
import '../../domain/ports/ocr_engine.dart';
import 'ocr_model_store.dart';
import 'paddle_worker.dart';

/// PP-OCRv5 through ONNX Runtime, in one long-lived background isolate: the
/// models are loaded once and kept, and the UI isolate never decodes, resizes
/// or post-processes anything. This class is only the root-isolate side: it
/// starts the worker, sends it one page at a time, and turns its replies,
/// the timeout and a cancel into an [OcrOutcome].
///
/// It uses no network: models come from the APK (`OcrModelStore`).
class PaddleOcrEngine implements OcrEngine {
  PaddleOcrEngine({
    required this.registry,
    required this.models,
    required this.logger,
  });

  final OcrLanguagePackRegistry registry;
  final OcrModelStore models;
  final AppLogger logger;

  Isolate? _isolate;
  SendPort? _worker;
  ReceivePort? _replies;
  Future<void>? _starting;
  final _pending = <int, _Call>{};
  var _nextId = 0;

  Future<void> _start() {
    if (_worker != null) return Future.value();
    return _starting ??= _spawn().whenComplete(() => _starting = null);
  }

  Future<void> _spawn() async {
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((Object? message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is List) {
        final call = _pending[message[0] as int];
        if (call == null) return;
        if (message[1] == WorkerOps.progress) {
          call.onProgress?.call(
            message[2] as String,
            message[3] as int,
            message[4] as int,
          );
        } else {
          _pending.remove(message[0] as int);
          if (!call.done.isCompleted) call.done.complete(message[2]);
        }
      }
    });
    _replies = replies;
    _isolate = await Isolate.spawn(ocrWorkerMain, <Object?>[
      replies.sendPort,
      RootIsolateToken.instance,
    ]);
    _worker = await ready.future;
  }

  _Call _send(
    String op,
    Object? data, {
    void Function(String, int, int)? onProgress,
  }) {
    final id = _nextId++;
    final call = _Call(id, onProgress);
    _pending[id] = call;
    _worker!.send(<Object?>[id, op, data]);
    return call;
  }

  void _cancelWorker(int id) =>
      _worker?.send(<Object?>[-1, WorkerOps.cancel, id]);

  @override
  Future<void> preload(String packId) async {
    try {
      final pack = registry.byId(packId);
      if (pack == null) return;
      final paths = await models.resolve(pack);
      await _start();
      final call = _send(WorkerOps.load, paths.toMap());
      await call.done.future.timeout(OcrConfig.preloadTimeout);
    } catch (error) {
      logger.debug('OCR preload skipped (${error.runtimeType})');
    }
  }

  @override
  Future<OcrOutcome> recognize(
    UprightImage image, {
    required String packId,
    Duration timeout = OcrConfig.pageTimeout,
    OcrCancellation? cancellation,
    void Function(OcrProgress progress)? onProgress,
  }) async {
    if (cancellation?.isCancelled ?? false) return const OcrCancelled();
    final pack = registry.byId(packId);
    if (pack == null) return const OcrFailed(OcrFailureReason.modelUnavailable);

    final OcrModelPaths paths;
    try {
      paths = await models.resolve(pack);
      await _start();
    } on OcrModelException {
      return const OcrFailed(OcrFailureReason.modelUnavailable);
    } catch (error) {
      logger.error('OCR engine could not start', error);
      return const OcrFailed(OcrFailureReason.engineError);
    }
    if (cancellation?.isCancelled ?? false) return const OcrCancelled();

    final call = _send(
      WorkerOps.recognize,
      <String, Object?>{'models': paths.toMap(), 'image': image.path},
      onProgress: onProgress == null
          ? null
          : (stage, done, total) => onProgress(_progress(stage, done, total)),
    );

    final outcome = Completer<OcrOutcome>();
    final timer = Timer(timeout, () {
      if (outcome.isCompleted) return;
      _cancelWorker(call.id);
      outcome.complete(OcrTimedOut(timeout));
    });
    unawaited(
      cancellation?.whenCancelled.then((_) {
        if (outcome.isCompleted) return;
        _cancelWorker(call.id);
        outcome.complete(const OcrCancelled());
      }),
    );
    unawaited(
      call.done.future.then((reply) async {
        if (outcome.isCompleted) return;
        outcome.complete(await _toOutcome(reply, packId, image, paths));
      }),
    );
    try {
      return await outcome.future;
    } finally {
      timer.cancel();
    }
  }

  OcrProgress _progress(String stage, int done, int total) => OcrProgress(
    switch (stage) {
      'loadingModels' => OcrStage.loadingModels,
      'detecting' => OcrStage.detecting,
      _ => OcrStage.recognizing,
    },
    done: done,
    total: total,
  );

  Future<OcrOutcome> _toOutcome(
    Object? reply,
    String packId,
    UprightImage image,
    OcrModelPaths paths,
  ) async {
    if (reply is! Map) return const OcrFailed(OcrFailureReason.engineError);
    switch (reply['status']) {
      case 'ok':
        final flat = reply['lines']! as List;
        final lines = <OcrLine>[];
        for (
          var i = 0;
          i + workerLineStride <= flat.length;
          i += workerLineStride
        ) {
          lines.add(
            OcrLine(
              text: flat[i] as String,
              confidence: (flat[i + 1] as num).toDouble(),
              row: flat[i + 2] as int,
              quad: [
                for (var k = 0; k < 4; k++)
                  OcrPoint(
                    (flat[i + 3 + 2 * k] as num).toDouble(),
                    (flat[i + 4 + 2 * k] as num).toDouble(),
                  ),
              ],
            ),
          );
        }
        return OcrSuccess(
          OcrResult(
            lines: lines,
            packId: packId,
            duration: Duration(microseconds: reply['recUs']! as int),
            imageWidth: reply['width']! as int,
            imageHeight: reply['height']! as int,
          ),
        );
      case 'cancelled':
        return const OcrCancelled();
      default:
        final reason = reply['reason'];
        if (reason == WorkerFailure.modelUnavailable) {
          // A file that failed its SHA-256 is removed, so the next run
          // extracts it from the APK again.
          for (final name in (reply['bad'] as List?) ?? const []) {
            for (final file in [paths.det, paths.rec, paths.dict]) {
              if (file.name == name) await models.forget(file);
            }
          }
          return const OcrFailed(OcrFailureReason.modelUnavailable);
        }
        if (reason == WorkerFailure.imageUnreadable) {
          return const OcrFailed(OcrFailureReason.imageUnreadable);
        }
        return const OcrFailed(OcrFailureReason.engineError);
    }
  }

  @override
  Future<void> release() async {
    if (_worker == null) return;
    try {
      await _send(
        WorkerOps.release,
        null,
      ).done.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      // Best effort.
    }
  }

  @override
  Future<void> dispose() async {
    if (_worker != null) {
      try {
        await _send(
          WorkerOps.release,
          null,
        ).done.future.timeout(const Duration(seconds: 10));
      } catch (_) {
        // The isolate is killed below anyway.
      }
    }
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    _isolate = null;
    _worker = null;
    _replies = null;
    _pending.clear();
  }
}

class _Call {
  _Call(this.id, this.onProgress);

  final int id;
  final void Function(String stage, int done, int total)? onProgress;
  final done = Completer<Object?>();
}
