import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../domain/entities/page_crop_outcome.dart';
import '../../domain/ocr/ocr_cancellation.dart';
import '../../domain/ports/page_cropper.dart';
import 'crop_page_job.dart';

/// [PageCropper] that runs [cropPageSync] in its own isolate (the UI isolate
/// is never involved).
///
/// The isolate is spawned, not run with `Isolate.run`, so that it can be
/// **killed**: on a timeout or a cancel it is stopped at once, and only after
/// it has exited is the target removed, so no file can appear afterwards.
class IsolatePageCropper implements PageCropper {
  const IsolatePageCropper();

  /// How long to wait for a killed isolate to exit before giving up (the cache
  /// is purged at start-up anyway).
  static const _exitWait = Duration(seconds: 2);

  @override
  Future<PageCropOutcome> crop({
    required String source,
    required String target,
    required int maxSide,
    required int jpegQuality,
    required int? focalLength35mm,
    required Duration timeout,
    OcrCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return const PageWholeFrame(WholeFrameReason.cancelled);
    }
    final job = CropJob(
      source: source,
      target: target,
      maxSide: maxSide,
      jpegQuality: jpegQuality,
      focalLength35mm: focalLength35mm,
    );
    final results = ReceivePort();
    final exits = ReceivePort();
    final errors = ReceivePort();
    final answer = Completer<CropJobResult>();
    final exited = Completer<void>();
    Timer? timer;
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn<_Start>(
        _run,
        _Start(job, results.sendPort),
        onExit: exits.sendPort,
        onError: errors.sendPort,
        errorsAreFatal: true,
      );
      results.listen((message) {
        if (message is CropJobResult && !answer.isCompleted) {
          answer.complete(message);
        }
      });
      errors.listen((_) {
        if (!answer.isCompleted) {
          answer.complete(
            const CropJobResult.wholeFrame(WholeFrameReason.failed),
          );
        }
      });
      exits.listen((_) {
        if (!exited.isCompleted) exited.complete();
        if (!answer.isCompleted) {
          answer.complete(
            const CropJobResult.wholeFrame(WholeFrameReason.failed),
          );
        }
      });
      timer = Timer(timeout, () {
        if (!answer.isCompleted) {
          answer.complete(
            const CropJobResult.wholeFrame(WholeFrameReason.timedOut),
          );
        }
      });
      unawaited(
        cancellation?.whenCancelled.then((_) {
          if (!answer.isCompleted) {
            answer.complete(
              const CropJobResult.wholeFrame(WholeFrameReason.cancelled),
            );
          }
        }),
      );
      final result = await answer.future;
      if (result.reason != null) {
        // Stopped or failed: make sure it is gone before the target is looked at.
        isolate.kill(priority: Isolate.immediate);
        await exited.future.timeout(_exitWait, onTimeout: () {});
        await _removeTarget(target);
      }
      return result.toOutcome();
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      await _removeTarget(target);
      return const PageWholeFrame(WholeFrameReason.failed);
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

  final CropJob job;
  final SendPort reply;
}

void _run(_Start start) {
  start.reply.send(cropPageSync(start.job));
}
