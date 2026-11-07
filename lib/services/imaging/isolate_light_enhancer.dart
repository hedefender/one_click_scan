import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../domain/ocr/ocr_cancellation.dart';
import '../../domain/ports/light_enhancer.dart';
import 'light_jobs.dart';

/// [LightEnhancer] that runs [enhanceLightSync] in its own isolate (never the
/// UI isolate). Like the crop (ADR-029) the isolate is spawned, so a timeout or
/// a cancel **kills** it, and the target is removed only after it has exited.
class IsolateLightEnhancer implements LightEnhancer {
  const IsolateLightEnhancer();

  static const _exitWait = Duration(seconds: 2);

  @override
  Future<bool> enhance({
    required String source,
    required String target,
    required int jpegQuality,
    required Duration timeout,
    OcrCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) return false;
    final results = ReceivePort();
    final exits = ReceivePort();
    final errors = ReceivePort();
    final answer = Completer<bool>();
    final exited = Completer<void>();
    Timer? timer;
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<_Start>(
        _run,
        _Start(
          EnhanceJob(source: source, target: target, jpegQuality: jpegQuality),
          results.sendPort,
        ),
        onExit: exits.sendPort,
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
      results.listen((message) {
        if (message is bool && !answer.isCompleted) answer.complete(message);
      });
      errors.listen((_) {
        if (!answer.isCompleted) answer.complete(false);
      });
      exits.listen((_) {
        if (!exited.isCompleted) exited.complete();
        if (!answer.isCompleted) answer.complete(false);
      });
      timer = Timer(timeout, () {
        if (!answer.isCompleted) answer.complete(false);
      });
      unawaited(
        cancellation?.whenCancelled.then((_) {
          if (!answer.isCompleted) answer.complete(false);
        }),
      );
      final done = await answer.future;
      if (!done) {
        isolate.kill(priority: Isolate.immediate);
        await exited.future.timeout(_exitWait, onTimeout: () {});
        await _removeTarget(target);
      }
      return done;
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      await _removeTarget(target);
      return false;
    } finally {
      timer?.cancel();
      results.close();
      exits.close();
      errors.close();
    }
  }

  Future<void> _removeTarget(String target) async {
    try {
      final file = File(target);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // The cache is purged at the next start-up anyway.
    }
  }
}

class _Start {
  const _Start(this.job, this.reply);

  final EnhanceJob job;
  final SendPort reply;
}

void _run(_Start start) {
  start.reply.send(enhanceLightSync(start.job));
}
