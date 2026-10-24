import 'dart:async';

import 'package:equatable/equatable.dart';

import '../entities/ocr_outcome.dart';
import '../entities/ocr_progress.dart';
import '../entities/upright_image.dart';
import '../ocr/confidence_filter.dart';
import '../ocr/ocr_cancellation.dart';
import '../ports/ocr_engine.dart';
import '../ports/ocr_work_store.dart';
import 'prepare_image_for_ocr.dart';

/// Where a page is in the pipeline.
enum OcrPageStatus { queued, preparing, recognizing, done }

class OcrPageState extends Equatable {
  const OcrPageState({
    required this.key,
    required this.status,
    this.progress,
    this.outcome,
    this.image,
  });

  /// Identifies the page (the path of the captured shot).
  final String key;
  final OcrPageStatus status;

  /// Latest progress report while preparing or recognizing.
  final OcrProgress? progress;

  /// Set when [status] is [OcrPageStatus.done].
  final OcrOutcome? outcome;

  /// The working copy, once it exists.
  final UprightImage? image;

  @override
  List<Object?> get props => [key, status, progress, outcome, image];
}

class OcrSessionSnapshot extends Equatable {
  const OcrSessionSnapshot({
    required this.packId,
    required this.pages,
    required this.closed,
  });

  final String packId;

  /// In capture order.
  final List<OcrPageState> pages;

  /// No more pages will be added.
  final bool closed;

  bool get allDone => pages.every((p) => p.status == OcrPageStatus.done);

  /// Closed and every page has an outcome.
  bool get isFinished => closed && allDone;

  @override
  List<Object?> get props => [packId, pages, closed];
}

/// Reads the pages of one scan, one after the other, in the background.
///
/// Pipelining: [add] returns at once and the page is processed as soon as the
/// previous one is done, while the camera takes the next shot. Only one image
/// is processed at a time (memory). Results are collected until [close] and
/// [finished]. Nothing here ever throws to the UI: a failed page is an
/// [OcrOutcome].
class OcrSession {
  OcrSession({
    required this.packId,
    required this._engine,
    required this._prepare,
    required this._workStore,
  });

  final String packId;
  final OcrEngine _engine;
  final PrepareImageForOcr _prepare;
  final OcrWorkStore _workStore;

  final _entries = <_Entry>[];
  final _controller = StreamController<OcrSessionSnapshot>.broadcast();
  final _finished = Completer<OcrSessionSnapshot>();
  var _closed = false;
  var _running = false;
  var _disposed = false;

  Stream<OcrSessionSnapshot> get snapshots => _controller.stream;

  OcrSessionSnapshot get snapshot => OcrSessionSnapshot(
    packId: packId,
    pages: [for (final e in _entries) e.state],
    closed: _closed,
  );

  /// Completes when the session is closed and every page has an outcome (or
  /// after [cancel]).
  Future<OcrSessionSnapshot> get finished => _finished.future;

  /// Queues a page. Ignored after [close] or [dispose].
  void add(String key, String sourcePath) {
    if (_closed || _disposed) return;
    _entries.add(_Entry(key, sourcePath));
    _emit();
    _pump();
  }

  /// The page was deleted by the user (Multi Page: delete the last shot).
  Future<void> remove(String key) async {
    final index = _entries.indexWhere((e) => e.key == key);
    if (index < 0) return;
    final entry = _entries.removeAt(index);
    entry.removed = true;
    entry.cancellation.cancel();
    if (!entry.processing) await _discard(entry);
    _emit();
    _maybeFinish();
  }

  /// No more pages are coming.
  void close() {
    if (_closed) return;
    _closed = true;
    _emit();
    _maybeFinish();
  }

  /// Stops everything: the running page is cancelled and the queued ones
  /// get the outcome [OcrCancelled]. Working copies stay until [dispose].
  Future<void> cancel() async {
    _closed = true;
    for (final e in _entries) {
      if (e.status == OcrPageStatus.done) continue;
      e.cancellation.cancel();
      if (!e.processing) {
        e.status = OcrPageStatus.done;
        e.outcome = const OcrCancelled();
      }
    }
    _emit();
    _maybeFinish();
  }

  /// Cancels, deletes the working copies and frees the engine's memory.
  Future<void> dispose() async {
    if (_disposed) return;
    await cancel();
    _disposed = true;
    for (final e in List.of(_entries)) {
      await _discard(e);
    }
    await _controller.close();
    try {
      await _engine.release();
    } catch (_) {
      // Releasing is best effort.
    }
  }

  void _pump() {
    if (_running || _disposed) return;
    final next = _entries.where((e) => e.status == OcrPageStatus.queued);
    if (next.isEmpty) {
      _maybeFinish();
      return;
    }
    _running = true;
    final entry = next.first;
    unawaited(
      _process(entry).whenComplete(() {
        _running = false;
        _pump();
      }),
    );
  }

  Future<void> _process(_Entry e) async {
    e.processing = true;
    try {
      if (e.cancellation.isCancelled) {
        _finish(e, const OcrCancelled());
        return;
      }
      e.status = OcrPageStatus.preparing;
      e.progress = const OcrProgress(OcrStage.preparingImage);
      _emit();
      try {
        e.image = await _prepare(e.sourcePath);
      } on ImagePreparationException catch (error) {
        _finish(e, OcrFailed(error.reason));
        return;
      }
      if (e.cancellation.isCancelled) {
        _finish(e, const OcrCancelled());
        return;
      }
      e.status = OcrPageStatus.recognizing;
      _emit();
      OcrOutcome outcome;
      try {
        outcome = await _engine.recognize(
          e.image!,
          packId: packId,
          cancellation: e.cancellation,
          onProgress: (progress) {
            if (e.removed || e.status != OcrPageStatus.recognizing) return;
            e.progress = progress;
            _emit();
          },
        );
      } catch (_) {
        outcome = const OcrFailed(OcrFailureReason.engineError);
      }
      if (outcome is OcrSuccess) {
        outcome = OcrSuccess(applyConfidenceFilter(outcome.result));
      }
      _finish(e, outcome);
    } finally {
      e.processing = false;
      if (e.removed) await _discard(e);
    }
  }

  void _finish(_Entry e, OcrOutcome outcome) {
    e.status = OcrPageStatus.done;
    e.progress = null;
    e.outcome = outcome;
    if (!e.removed) _emit();
  }

  Future<void> _discard(_Entry e) async {
    final image = e.image;
    e.image = null;
    if (image != null) {
      try {
        await _workStore.delete(image.path);
      } catch (_) {
        // The cache is purged at the next start-up anyway.
      }
    }
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(snapshot);
  }

  void _maybeFinish() {
    if (_finished.isCompleted) return;
    if (_closed && _entries.every((e) => e.status == OcrPageStatus.done)) {
      _finished.complete(snapshot);
    }
  }
}

class _Entry {
  _Entry(this.key, this.sourcePath);

  final String key;
  final String sourcePath;
  final cancellation = OcrCancellation();
  var status = OcrPageStatus.queued;
  OcrProgress? progress;
  OcrOutcome? outcome;
  UprightImage? image;
  var processing = false;
  var removed = false;

  OcrPageState get state => OcrPageState(
    key: key,
    status: status,
    progress: progress,
    outcome: outcome,
    image: image,
  );
}

/// Use case: starts the background reading of the pages of one scan.
class RecognizePages {
  const RecognizePages({
    required this._engine,
    required this._prepare,
    required this._workStore,
  });

  final OcrEngine _engine;
  final PrepareImageForOcr _prepare;
  final OcrWorkStore _workStore;

  /// A new session for one scan, with the language pack chosen by the user.
  OcrSession start({required String packId}) => OcrSession(
    packId: packId,
    engine: _engine,
    prepare: _prepare,
    workStore: _workStore,
  );

  /// Loads the models ahead of time (when the camera opens).
  Future<void> preload(String packId) => _engine.preload(packId);

  /// Frees the models again (the camera was left without a scan).
  Future<void> release() => _engine.release();
}
