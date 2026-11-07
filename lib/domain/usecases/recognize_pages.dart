import 'dart:async';

import 'package:equatable/equatable.dart';

import '../entities/ocr_outcome.dart';
import '../entities/ocr_progress.dart';
import '../entities/page_crop_outcome.dart';
import '../entities/upright_image.dart';
import '../imaging/page_crop_config.dart';
import '../ocr/confidence_filter.dart';
import '../ocr/ocr_cancellation.dart';
import '../ports/ocr_engine.dart';
import '../ports/ocr_work_store.dart';
import 'prepare_image_for_ocr.dart';
import 'straighten_page.dart';

/// Where a page is in the pipeline. [preparing] is the working copy and the
/// crop; [ready] is a page whose picture is made and that waits for the engine
/// (ADR-029).
enum OcrPageStatus { queued, preparing, ready, recognizing, done }

class OcrPageState extends Equatable {
  const OcrPageState({
    required this.key,
    required this.status,
    this.progress,
    this.outcome,
    this.image,
    this.crop,
    this.workingCopyDeleted = false,
  });

  /// Identifies the page (the path of the captured shot).
  final String key;
  final OcrPageStatus status;

  /// Latest progress report while preparing or recognizing.
  final OcrProgress? progress;

  /// Set when [status] is [OcrPageStatus.done].
  final OcrOutcome? outcome;

  /// The working copy, once it exists. After
  /// [OcrSession.releaseWorkingCopies] only its description is left.
  final UprightImage? image;

  /// What the crop made of the page; null until the crop step has run (and
  /// always null when the session has no crop step).
  final PageCropOutcome? crop;

  /// The file of [image] was deleted (the PDF is stored, ADR-018).
  final bool workingCopyDeleted;

  /// The picture of the page can still be read from the cache.
  bool get hasWorkingFile => image != null && !workingCopyDeleted;

  @override
  List<Object?> get props => [
    key,
    status,
    progress,
    outcome,
    image,
    crop,
    workingCopyDeleted,
  ];
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

  /// Pages whose picture is the straightened page.
  int get croppedCount => pages.where((p) => p.crop is PageCropped).length;

  /// Pages that kept the whole frame, by the reason (numbers for the log).
  Map<WholeFrameReason, int> get wholeFrameReasons {
    final counts = <WholeFrameReason, int>{};
    for (final page in pages) {
      final crop = page.crop;
      if (crop is PageWholeFrame) {
        counts[crop.reason] = (counts[crop.reason] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  List<Object?> get props => [packId, pages, closed];
}

/// Prepares and reads the pages of one scan in the background, in two stages
/// that overlap (ADR-029):
///
///  * **prepare**: the upright working copy and the crop of the page, one page
///    at a time, in capture order;
///  * **read**: the OCR on that picture, one page at a time, in capture order.
///
/// While page k is read, page k+1 is prepared, so the preparation hides behind
/// the reading and behind the time between the shots. A page that is prepared
/// waits for the engine as a file; at most [prepareAhead] of them wait, so the
/// memory is bounded (backpressure: the preparation pauses until the engine
/// takes one). [add] returns at once. Results are collected until [close] and
/// [finished]. Nothing here ever throws to the UI: a failed page is an
/// [OcrOutcome], and a failed crop is the whole frame.
class OcrSession {
  OcrSession({
    required this.packId,
    required this._engine,
    required this._prepare,
    required this._workStore,
    this._straighten,
    this.prepareAhead = PageCropConfig.prepareAhead,
  });

  final String packId;
  final OcrEngine _engine;
  final PrepareImageForOcr _prepare;
  final OcrWorkStore _workStore;

  /// The crop step; null on a platform without one (every page keeps the whole
  /// frame and has no crop outcome).
  final StraightenPage? _straighten;

  /// How many prepared pages may wait for the engine.
  final int prepareAhead;

  final _entries = <_Entry>[];
  final _controller = StreamController<OcrSessionSnapshot>.broadcast();
  final _finished = Completer<OcrSessionSnapshot>();
  var _closed = false;
  var _preparing = false;
  var _reading = false;
  var _disposed = false;
  var _readingStopped = false;

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

  /// The page was deleted by the user (Multi Page: delete the last shot). A
  /// crop that is running for it is stopped and its picture is deleted.
  Future<void> remove(String key) async {
    final index = _entries.indexWhere((e) => e.key == key);
    if (index < 0) return;
    final entry = _entries.removeAt(index);
    entry.removed = true;
    entry.cancellation.cancel();
    if (!entry.processing) await _discard(entry);
    _emit();
    _pump();
  }

  /// No more pages are coming.
  void close() {
    if (_closed) return;
    _closed = true;
    _emit();
    _maybeFinish();
  }

  /// Stops everything: the running stages are cancelled (a crop is killed) and
  /// the pages not being worked on get the outcome [OcrCancelled]. Working
  /// copies stay until [dispose].
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

  /// Stops the reading but not the preparation: the page being read is
  /// cancelled and the pages after it only get their picture (cropped as
  /// usual, a crop that runs is let to finish), with the outcome
  /// [OcrCancelled]. Used by "make the PDF without waiting for the text":
  /// every page still has its picture, so the PDF can be made.
  void stopReading() {
    if (_disposed) return;
    _readingStopped = true;
    for (final e in _entries) {
      if (e.status == OcrPageStatus.recognizing) e.cancellation.cancel();
    }
    _pump();
  }

  /// Deletes the files of the working copies of finished pages, so no picture
  /// of the user's documents stays in the cache once the PDF is stored. The
  /// results stay; the pages only lose the file their image was read from.
  Future<void> releaseWorkingCopies() async {
    for (final e in _entries) {
      if (e.processing || e.image == null || e.fileDeleted) continue;
      e.fileDeleted = true;
      try {
        await _workStore.delete(e.image!.path);
      } catch (_) {
        // The cache is purged at the next start-up anyway.
      }
    }
    _emit();
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
    if (_disposed) return;
    _pumpPrepare();
    _pumpRead();
    _maybeFinish();
  }

  /// Starts the preparation of the next queued page, unless one is running or
  /// [prepareAhead] prepared pages already wait for the engine.
  void _pumpPrepare() {
    if (_preparing) return;
    final waiting = _entries
        .where((e) => e.status == OcrPageStatus.ready)
        .length;
    if (waiting >= prepareAhead) return;
    final next = _entries.where((e) => e.status == OcrPageStatus.queued);
    if (next.isEmpty) return;
    _preparing = true;
    unawaited(
      _prepareStage(next.first).whenComplete(() {
        _preparing = false;
        _pump();
      }),
    );
  }

  /// Starts the reading of the earliest page that is not done, if its picture
  /// is ready (the reading is in capture order).
  void _pumpRead() {
    if (_reading) return;
    for (final e in _entries) {
      if (e.status == OcrPageStatus.done) continue;
      if (e.status != OcrPageStatus.ready) return;
      _reading = true;
      unawaited(
        _readStage(e).whenComplete(() {
          _reading = false;
          _pump();
        }),
      );
      return;
    }
  }

  Future<void> _prepareStage(_Entry e) async {
    e.preparing = true;
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
      final straighten = _straighten;
      if (straighten != null) {
        e.progress = const OcrProgress(OcrStage.straighteningPage);
        _emit();
        final result = await straighten(e.image!, cancellation: e.cancellation);
        e.image = result.image;
        e.crop = result.outcome;
      }
      if (e.cancellation.isCancelled || _readingStopped) {
        _finish(e, const OcrCancelled());
        return;
      }
      e.status = OcrPageStatus.ready;
      e.progress = null;
      _emit();
    } finally {
      e.preparing = false;
      if (e.removed || _disposed) await _discard(e);
    }
  }

  Future<void> _readStage(_Entry e) async {
    e.reading = true;
    try {
      if (e.cancellation.isCancelled || _readingStopped) {
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
      e.reading = false;
      if (e.removed || _disposed) await _discard(e);
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
    if (image != null && !e.fileDeleted) {
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
  PageCropOutcome? crop;

  /// A stage of this page is running (a removed page is cleaned up when the
  /// last one ends).
  var preparing = false;
  var reading = false;
  bool get processing => preparing || reading;
  var removed = false;

  /// The file of [image] was deleted by `releaseWorkingCopies`.
  var fileDeleted = false;

  OcrPageState get state => OcrPageState(
    key: key,
    status: status,
    progress: progress,
    outcome: outcome,
    image: image,
    crop: crop,
    workingCopyDeleted: fileDeleted,
  );
}

/// Use case: starts the background reading of the pages of one scan.
class RecognizePages {
  const RecognizePages({
    required this._engine,
    required this._prepare,
    required this._workStore,
    this.straighten,
  });

  final OcrEngine _engine;
  final PrepareImageForOcr _prepare;
  final OcrWorkStore _workStore;

  /// The crop step of every page; null where there is none.
  final StraightenPage? straighten;

  /// A new session for one scan, with the language pack chosen by the user.
  OcrSession start({required String packId}) => OcrSession(
    packId: packId,
    engine: _engine,
    prepare: _prepare,
    workStore: _workStore,
    straighten: straighten,
  );

  /// Loads the models ahead of time (when the camera opens).
  Future<void> preload(String packId) => _engine.preload(packId);

  /// Frees the models again (the camera was left without a scan).
  Future<void> release() => _engine.release();
}
