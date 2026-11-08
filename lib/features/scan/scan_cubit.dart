import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/scan_flow_mode.dart';
import '../../domain/entities/scan_mode.dart';
import '../../domain/entities/storage_folder.dart';
import '../../domain/lighting/flash_mode.dart';
import '../../domain/lighting/light_metric.dart';
import '../../domain/lighting/lighting_config.dart';
import '../../domain/lighting/low_light_debouncer.dart';
import '../../domain/lighting/low_light_policy.dart';
import '../../domain/ports/flash_preference_store.dart';
import '../../domain/mail/mail_provider.dart';
import '../../domain/ports/light_meter.dart';
import '../../domain/ports/multi_page_hint_store.dart';
import '../../domain/scan/page_budget_config.dart';
import '../../domain/scan/page_budget_estimator.dart';
import '../../domain/scan/scan_flow.dart' show ScanFlowCancellation;
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/recognize_pages.dart';
import '../../domain/usecases/store_scan_pages.dart';
import '../../services/camera/camera_service.dart';
import '../../services/scan_files/scan_temp_store.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import 'scan_state.dart';

/// State machine of one scan: check folder, open camera, take one or many
/// pages (kept in the cache), then store them in the user's folder.
class ScanCubit extends Cubit<ScanState> {
  ScanCubit({
    required this._loadSettings,
    required this._folderPicker,
    required this._camera,
    required this._storeScanPages,
    required this._recognizePages,
    required this._tempStore,
    required this._flashStore,
    required this._lightMeter,
    required this._logger,
    this._torchIdleTimeout = LightingConfig.torchIdleTimeout,
    this._torchSettleDelay = LightingConfig.torchSettleDelay,
    this._helpsMinPaperLevel = LightingConfig.enhancementHelpsMinPaperLevel,
    this._multiPageHints,
    this._providers = MailProviderRegistry.standard,
    this._budgetConfig = const PageBudgetConfig(),
  }) : super(const ScanState());

  final LoadSettings _loadSettings;
  final StorageFolderPicker _folderPicker;
  final CameraService _camera;
  final StoreScanPages _storeScanPages;
  final RecognizePages _recognizePages;
  final ScanTempStore _tempStore;
  final FlashPreferenceStore _flashStore;
  final LightMeter _lightMeter;
  final AppLogger _logger;

  /// Injectable so the torch rules are tested without waiting (ADR-031).
  final Duration _torchIdleTimeout;
  final Duration _torchSettleDelay;
  final double _helpsMinPaperLevel;

  /// The size limit of the provider and the numbers of the page budget
  /// (ADR-032); injectable so the tests need no real sizes.
  final MailProviderRegistry _providers;

  /// Remembers that the first-open hint of Multi Page was shown; null in
  /// tests that do not need it (no hint then).
  final MultiPageHintStore? _multiPageHints;
  final PageBudgetConfig _budgetConfig;

  /// How the scan goes on after the shot (read with the settings); decides
  /// what a dark shot does (ADR-030).
  var _flowMode = ScanFlowMode.preview;

  final _debouncer = LowLightDebouncer();
  StreamSubscription<LightMetric>? _lightSubscription;

  /// The flash chosen on the screen; On is for this use only.
  FlashMode _flash = FlashMode.off;

  /// Language pack of this scan, read once when the scan starts.
  String? _packId;

  /// Reads the pages in the background while the next ones are shot. Created
  /// with the first page; handed to the result screen once the scan is saved.
  OcrSession? _ocr;

  /// The models were loaded ahead of time and nobody has used them yet.
  var _preloaded = false;

  /// Stops the storing of the pictures while it runs (ADR-028).
  ScanFlowCancellation? _saving;

  /// Entry point (and "try again" after a denied permission or a missing
  /// folder). Nothing starts without an accessible folder.
  Future<void> start() async {
    emit(state.copyWith(phase: ScanPhase.starting));
    final settings = await _loadSettings();
    _packId = settings.ocrPackId;
    _flowMode = settings.effectiveScanFlowMode;
    final providerId = settings.mailProvider;
    final estimator = providerId == null
        ? PageBudgetEstimator.strictest(_providers.all, config: _budgetConfig)
        : PageBudgetEstimator.forProvider(
            _providers.resolve(providerId),
            config: _budgetConfig,
          );
    emit(state.copyWith(budgetEstimator: estimator));
    final folder = settings.storageFolder;
    final accessible = folder != null && await _hasAccess(folder);
    if (isClosed) return;
    if (!accessible) {
      emit(state.copyWith(phase: ScanPhase.folderUnavailable));
      return;
    }
    await _openCamera();
  }

  void setMode(ScanMode mode) {
    if (!state.canChangeMode) return;
    final hints = _multiPageHints;
    final firstMulti = mode == ScanMode.multi && hints != null && !hints.seen;
    emit(state.copyWith(mode: mode, showMultiHint: firstMulti));
  }

  /// The first-open hint of Multi Page is on the screen: it never shows again
  /// (the flag is stored at once, so a killed app does not repeat it).
  Future<void> multiHintShown() async {
    if (state.showMultiHint) emit(state.copyWith(showMultiHint: false));
    await _multiPageHints?.markSeen();
  }

  Future<void> capture() async {
    if (!state.canCapture) return;
    emit(
      state.copyWith(
        phase: ScanPhase.capturing,
        captureFailed: false,
        saveCancelled: false,
      ),
    );
    try {
      _resetTorchIdle();
      await _torchReadyForShot();
      final page = await _camera.capture(order: state.pages.length + 1);
      if (isClosed) {
        await _tempStore.delete([page.path]);
        return;
      }
      emit(
        state.copyWith(
          phase: state.mode == ScanMode.single
              ? ScanPhase.capturing
              : ScanPhase.ready,
          pages: [...state.pages, page],
          clearDarkBar: true,
        ),
      );
      _resetTorchIdle();
      _readInBackground(page.path);
      if (state.mode == ScanMode.multi) {
        // The rate of the shots is not slowed down: the light of the shot is
        // measured behind the camera screen (ADR-030).
        unawaited(_assessMulti(page.path));
        return;
      }
      if (await _assessSingle(page.path)) return;
    } on CameraCaptureException catch (error, stackTrace) {
      _logger.error('Capture failed', error, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(phase: ScanPhase.ready, captureFailed: true));
      return;
    }
    if (state.mode == ScanMode.single) await save();
  }

  /// Measures a shot. Never throws; null when it could not be measured (then
  /// the shot is never called dark).
  Future<LightMetric?> _measure(String path) async {
    try {
      return await _lightMeter.measureFile(path);
    } catch (_) {
      return null;
    }
  }

  /// Single Page: the decision comes before anything is stored. Returns true
  /// when the dialog waits for the user (the save is not started).
  Future<bool> _assessSingle(String path) async {
    final settings = await _loadSettings();
    _flowMode = settings.effectiveScanFlowMode;
    final metric = await _measure(path);
    if (isClosed || !state.pages.any((p) => p.path == path)) return true;
    final action = LowLightPolicy.onCapture(
      metric: metric,
      mode: ScanMode.single,
      flow: _flowMode,
    );
    final veryDark = [
      if (LowLightPolicy.retakeFirst(metric, helpsMin: _helpsMinPaperLevel))
        path,
    ];
    switch (action) {
      case LowLightAction.askNow:
        emit(
          state.copyWith(
            phase: ScanPhase.ready,
            lightPrompt: LightPrompt.singleShot,
            darkPages: [path],
            veryDarkPages: veryDark,
          ),
        );
        return true;
      case LowLightAction.bannerLater:
        emit(
          state.copyWith(
            phase: ScanPhase.ready,
            darkPages: [path],
            veryDarkPages: veryDark,
          ),
        );
        return false;
      case LowLightAction.markPage:
      case LowLightAction.none:
        emit(state.copyWith(phase: ScanPhase.ready));
        return false;
    }
  }

  /// Multi Page: a mark, never a stop. The bar offers a new shot of the last
  /// page; the summary before the send is in [finish].
  Future<void> _assessMulti(String path) async {
    final metric = await _measure(path);
    if (isClosed || !state.pages.any((p) => p.path == path)) return;
    final action = LowLightPolicy.onCapture(
      metric: metric,
      mode: ScanMode.multi,
      flow: _flowMode,
    );
    if (action == LowLightAction.none) return;
    final isLast = state.pages.last.path == path;
    emit(
      state.copyWith(
        darkPages: [...state.darkPages, path],
        veryDarkPages: [
          ...state.veryDarkPages,
          if (LowLightPolicy.retakeFirst(metric, helpsMin: _helpsMinPaperLevel))
            path,
        ],
        darkBarPage: action == LowLightAction.markPage && isLast ? path : null,
      ),
    );
  }

  /// The answer to the dialog of the Single shot or to the summary before the
  /// send (ADR-030).
  Future<void> resolveLowLight(LowLightChoice choice) async {
    final prompt = state.lightPrompt;
    if (prompt == LightPrompt.none) return;
    switch (choice) {
      case LowLightChoice.retake:
        if (prompt == LightPrompt.singleShot) {
          await _dropDarkPages();
        } else {
          // Back to the camera: the user takes the pages again as they wish.
          emit(state.copyWith(lightPrompt: LightPrompt.none));
        }
      case LowLightChoice.continueAnyway:
        emit(
          state.copyWith(
            lightPrompt: LightPrompt.none,
            darkPages: const [],
            clearDarkBar: true,
          ),
        );
        await save();
      case LowLightChoice.continueWithEnhancement:
        for (final key in state.darkPages) {
          // The correction is made in the queue; the PDF waits for it.
          unawaited(_ocr?.requestEnhance(key));
        }
        emit(
          state.copyWith(
            lightPrompt: LightPrompt.none,
            darkPages: const [],
            clearDarkBar: true,
          ),
        );
        await save();
    }
  }

  /// "New shot" of a dark Single shot: the shot never reached the folder or
  /// the Gallery, so dropping it leaves nothing (like the undo of a page).
  Future<void> _dropDarkPages() async {
    final paths = [for (final page in state.pages) page.path];
    for (final path in paths) {
      await _ocr?.remove(path);
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        pages: const [],
        darkPages: const [],
        lightPrompt: LightPrompt.none,
        clearDarkBar: true,
      ),
    );
    await _tempStore.delete(paths);
  }

  /// Multi: "New shot" of the last, dark page: the same as the undo.
  Future<void> retakeDarkPage() async {
    final path = state.darkBarPage;
    if (path == null) return;
    if (state.pages.isEmpty || state.pages.last.path != path) {
      emit(state.copyWith(clearDarkBar: true));
      return;
    }
    await deleteLast();
  }

  /// Closes the bar without a decision; the page stays flagged for the summary.
  void dismissDarkBar() => emit(state.copyWith(clearDarkBar: true));

  /// Off -> Auto -> On. Off and Auto are remembered, On is for this use only.
  Future<void> cycleFlash() => setFlash(_flash.next);

  Future<void> setFlash(FlashMode mode) async {
    if (!state.hasFlash) return;
    _flash = mode;
    emit(state.copyWith(flashMode: mode));
    await _camera.setFlashMode(mode);
    // Off and Auto put the torch out inside setFlashMode; On lights it here
    // (when the camera is on screen) after the mode is applied.
    _noteTorch();
    await _syncTorch();
    await _flashStore.save(mode);
  }

  /// Tap-to-focus. The tap also counts as use for the torch timeout.
  Future<void> focusAt(Offset point) {
    _resetTorchIdle();
    return _camera.focusAt(point);
  }

  /// The message of the idle timeout was shown.
  void torchIdleOffShown() {
    if (state.torchIdleOff) emit(state.copyWith(torchIdleOff: false));
  }

  // ----- Torch (flash On), ADR-031 -----

  Timer? _idleTimer;
  Timer? _settleTimer;
  bool _settling = false;
  bool _inactive = false;
  bool _torchNoted = false;
  Future<void> _torchQueue = Future<void>.value();

  /// The torch must be lit exactly while the camera is on the screen, the
  /// choice is On, and nothing (dialog, error, save, background) covers it.
  bool get _torchWanted =>
      _flash == FlashMode.on &&
      _camera.hasFlash &&
      !_inactive &&
      !isClosed &&
      (state.phase == ScanPhase.ready || state.phase == ScanPhase.capturing) &&
      state.lightPrompt == LightPrompt.none &&
      !state.captureFailed;

  /// Brings the real torch to what it must be. Serial, so two quick changes
  /// cannot cross each other.
  Future<void> _syncTorch() {
    return _torchQueue = _torchQueue.then((_) async {
      final want = _torchWanted;
      if (want != _camera.torchLit) await _camera.setTorchLit(want);
      _noteTorch();
    });
  }

  /// Bookkeeping when the real torch changed: forget the old samples, wait for
  /// the exposure to settle, restart the timeout.
  void _noteTorch() {
    final lit = _camera.torchLit;
    if (lit == _torchNoted) return;
    _torchNoted = lit;
    if (isClosed) return;
    _debouncer.restart();
    _settling = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(_torchSettleDelay, () => _settling = false);
    _resetTorchIdle();
    emit(state.copyWith(torchLit: lit));
  }

  /// The shot waits for a torch that was lit a moment ago to settle.
  Future<void> _torchReadyForShot() async {
    await _syncTorch();
    if (_camera.torchLit && _settling) {
      await Future<void>.delayed(_torchSettleDelay);
    }
  }

  void _resetTorchIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_camera.torchLit && !isClosed) {
      _idleTimer = Timer(_torchIdleTimeout, _onTorchIdle);
    }
  }

  Future<void> _onTorchIdle() async {
    _idleTimer = null;
    if (isClosed || !_camera.torchLit) return;
    emit(state.copyWith(torchIdleOff: true));
    await setFlash(FlashMode.auto);
  }

  /// Puts the torch out at once (until the camera is wanted again).
  Future<void> _torchOff() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    await _camera.setTorchLit(false);
    _noteTorch();
  }

  @override
  void onChange(Change<ScanState> change) {
    super.onChange(change);
    final before = change.currentState;
    final after = change.nextState;
    if (before.phase != after.phase ||
        before.lightPrompt != after.lightPrompt ||
        before.captureFailed != after.captureFailed) {
      // Runs after this emit, never inside it.
      unawaited(_syncTorch());
    }
  }

  /// The screen lost the focus (lock screen, notifications, a system dialog):
  /// the torch goes out at once and comes back with [onForeground].
  Future<void> onInactive() async {
    _inactive = true;
    await _torchOff();
  }

  /// Multi-page: removes the last shot.
  Future<void> deleteLast() async {
    if (state.phase != ScanPhase.ready || !state.hasPages) return;
    final removed = state.pages.last;
    emit(
      state.copyWith(
        pages: state.pages.sublist(0, state.pages.length - 1),
        darkPages: [
          for (final path in state.darkPages)
            if (path != removed.path) path,
        ],
        clearDarkBar: true,
        captureFailed: false,
        saveCancelled: false,
      ),
    );
    await _ocr?.remove(removed.path);
    await _tempStore.delete([removed.path]);
  }

  /// Multi-page "Done".
  Future<void> finish() async {
    if (!state.canFinish) return;
    final settings = await _loadSettings();
    _flowMode = settings.effectiveScanFlowMode;
    if (LowLightPolicy.needsSummary(
      flow: _flowMode,
      undecidedDarkPages: state.darkPages.length,
    )) {
      // A dark page is never sent silently in One Click.
      emit(state.copyWith(lightPrompt: LightPrompt.summary));
      return;
    }
    await save();
  }

  /// Stores the pages. Also the "try again" of a failed save: the pages are
  /// still in the cache, nothing is lost.
  Future<void> save() async {
    final canRun =
        state.hasPages &&
        (state.phase == ScanPhase.ready ||
            state.phase == ScanPhase.capturing ||
            state.phase == ScanPhase.saveFailed);
    if (!canRun) return;
    emit(state.copyWith(phase: ScanPhase.saving, saveCancelled: false));
    final cancellation = _saving = ScanFlowCancellation();

    try {
      final settings = await _loadSettings();
      final folder = settings.storageFolder;
      if (folder == null || !await _hasAccess(folder)) {
        if (isClosed) return;
        emit(state.copyWith(phase: ScanPhase.folderUnavailable));
        return;
      }
      final stored = await _storeScanPages(
        pages: state.pages,
        folder: folder,
        saveToGallery: settings.saveToGallery,
        cancellation: cancellation,
      );
      if (isClosed) return;
      await _torchOff();
      await _stopLightAnalysis();
      await _camera.close();
      unawaited(_ocrSubscription?.cancel());
      _ocrSubscription = null;
      _ocr?.close();
      emit(state.copyWith(phase: ScanPhase.saved, result: stored, ocr: _ocr));
    } on ScanStoreCancelled {
      if (isClosed) return;
      await _afterSaveCancelled();
    } on ScanStoreException catch (error, stackTrace) {
      _logger.error('Storing the scan failed', error, stackTrace);
      if (isClosed) return;
      if (error.failure == ScanStoreFailure.noAccess) {
        emit(state.copyWith(phase: ScanPhase.folderUnavailable));
      } else {
        emit(state.copyWith(phase: ScanPhase.saveFailed));
      }
    } catch (error, stackTrace) {
      _logger.error('Storing the scan failed unexpectedly', error, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(phase: ScanPhase.saveFailed));
    } finally {
      _saving = null;
    }
  }

  /// "Cancel" (or Back) while the pictures are written. The store rolls back
  /// what it wrote; the shots stay in the cache and the camera screen returns.
  void cancelSaving() {
    if (!state.canCancelSaving) return;
    _saving?.cancel();
  }

  /// Back to the camera after a cancelled save. Multi keeps its shots; Single
  /// drops the one shot (it was taken only to be saved).
  Future<void> _afterSaveCancelled() async {
    if (state.mode == ScanMode.single) {
      final paths = [for (final page in state.pages) page.path];
      for (final path in paths) {
        await _ocr?.remove(path);
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          phase: ScanPhase.ready,
          pages: const [],
          darkPages: const [],
          saveCancelled: true,
        ),
      );
      await _tempStore.delete(paths);
      return;
    }
    emit(state.copyWith(phase: ScanPhase.ready, saveCancelled: true));
  }

  /// "Try again" from the folder warning, after the user fixed the folder in
  /// Settings. Keeps the pages already taken.
  Future<void> retryAfterFolderFix() async {
    if (state.phase != ScanPhase.folderUnavailable) return;
    await start();
    // A single-page scan saves right after the shot; if that save was
    // interrupted by the folder problem, finish it now.
    if (state.phase == ScanPhase.ready &&
        state.mode == ScanMode.single &&
        state.hasPages) {
      await save();
    }
  }

  /// "Try again" after a denied camera permission.
  Future<void> retryCamera() async {
    if (state.phase != ScanPhase.permissionDenied &&
        state.phase != ScanPhase.cameraUnavailable) {
      return;
    }
    await start();
  }

  Future<void> openAppSettings() => _camera.openAppSettings();

  /// Leaving the scan: nothing of an unfinished scan may stay behind.
  Future<void> cancel() async {
    await _discardUnsavedPages();
    await _torchOff();
    await _stopLightAnalysis();
    await _camera.close();
  }

  /// Cache files of pages that were never stored. After a successful save the
  /// result screen still shows them as thumbnails and deletes them itself.
  Future<void> _discardUnsavedPages() async {
    if (state.phase == ScanPhase.saved) return;
    await _stopReading();
    if (!state.hasPages) return;
    final paths = [for (final page in state.pages) page.path];
    if (!isClosed) {
      emit(
        state.copyWith(
          pages: const [],
          darkPages: const [],
          lightPrompt: LightPrompt.none,
          clearDarkBar: true,
        ),
      );
    }
    await _tempStore.delete(paths);
  }

  /// App went to the background: release the camera.
  Future<void> onBackground() async {
    if (state.phase != ScanPhase.ready) return;
    emit(state.copyWith(phase: ScanPhase.paused));
    await _torchOff();
    await _stopLightAnalysis();
    await _camera.close();
  }

  /// App came back: reopen the camera, or re-check a denied permission (the
  /// user may have granted it in the system settings).
  Future<void> onForeground() async {
    if (_inactive) {
      _inactive = false;
      unawaited(_syncTorch());
    }
    switch (state.phase) {
      case ScanPhase.paused:
        await _openCamera();
      case ScanPhase.permissionDenied:
        await retryCamera();
      case _:
        break;
    }
  }

  /// Starts reading a shot at once, while the camera goes on. Never delays
  /// or fails the scan: the session reports problems as outcomes.
  void _readInBackground(String path) {
    final packId = _packId;
    if (packId == null) return;
    var session = _ocr;
    if (session == null) {
      session = _ocr = _recognizePages.start(packId: packId);
      // The size of each prepared page feeds the page budget (ADR-032).
      _ocrSubscription = session.snapshots.listen(_onOcrSnapshot);
    }
    session.add(path, path);
  }

  StreamSubscription<OcrSessionSnapshot>? _ocrSubscription;

  void _onOcrSnapshot(OcrSessionSnapshot snapshot) {
    if (isClosed) return;
    final bytes = <String, int>{
      for (final page in snapshot.pages)
        if (page.imageBytes != null && !page.workingCopyDeleted)
          page.key: page.imageBytes!,
    };
    if (_sameBytes(bytes, state.pageBytes)) return;
    emit(state.copyWith(pageBytes: bytes));
  }

  bool _sameBytes(Map<String, int> a, Map<String, int> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  /// The scan was abandoned: stop reading and drop the working copies.
  Future<void> _stopReading() async {
    unawaited(_ocrSubscription?.cancel());
    _ocrSubscription = null;
    final session = _ocr;
    _ocr = null;
    if (session != null) {
      await session.dispose(); // also frees the models
    } else if (_preloaded) {
      await _recognizePages.release();
    }
    _preloaded = false;
  }

  Future<void> _openCamera() async {
    final result = await _camera.open();
    if (isClosed) {
      await _camera.close();
      return;
    }
    if (result == CameraOpenResult.ready) {
      // Off and Auto come from the settings; On lives only in this use, so
      // after a return from the background it is still On (ADR-030).
      _flash = state.phase == ScanPhase.paused ? _flash : _flashStore.load();
      if (_camera.hasFlash) await _camera.setFlashMode(_flash);
      _startLightAnalysis();
    }
    // A camera that was (re)opened has its torch out; the light comes back
    // after the screen shows the camera again, when the choice is On.
    _noteTorch();
    final packId = _packId;
    if (result == CameraOpenResult.ready && packId != null) {
      // Loads the models while the user frames the page; best effort.
      _preloaded = true;
      unawaited(_recognizePages.preload(packId));
    }
    emit(
      state.copyWith(
        flashMode: _flash,
        hasFlash: result == CameraOpenResult.ready && _camera.hasFlash,
        phase: switch (result) {
          CameraOpenResult.ready => ScanPhase.ready,
          CameraOpenResult.permissionDenied => ScanPhase.permissionDenied,
          CameraOpenResult.unavailable => ScanPhase.cameraUnavailable,
        },
      ),
    );
  }

  void _startLightAnalysis() {
    _debouncer.reset();
    _lightSubscription?.cancel();
    _lightSubscription = _camera.lightSamples.listen((metric) {
      // Samples taken while the torch settles are dropped (ADR-031).
      if (isClosed || _settling) return;
      final low = _debouncer.add(metric);
      if (low != state.lowLight) emit(state.copyWith(lowLight: low));
    });
    _camera.startLightAnalysis();
  }

  Future<void> _stopLightAnalysis() async {
    _camera.stopLightAnalysis();
    // Not awaited: on a broadcast stream the future can wait for the camera.
    unawaited(_lightSubscription?.cancel());
    _lightSubscription = null;
    if (!isClosed && state.lowLight) emit(state.copyWith(lowLight: false));
  }

  Future<bool> _hasAccess(StorageFolder folder) async {
    try {
      return await _folderPicker.hasAccess(folder);
    } catch (error, stackTrace) {
      _logger.error('Storage folder access check failed', error, stackTrace);
      return false;
    }
  }

  @override
  Future<void> close() async {
    await _discardUnsavedPages();
    await _torchOff();
    await _stopLightAnalysis();
    await _camera.close();
    _settleTimer?.cancel();
    _idleTimer?.cancel();
    return super.close();
  }
}
