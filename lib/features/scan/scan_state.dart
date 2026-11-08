import 'package:equatable/equatable.dart';

import '../../domain/entities/captured_page.dart';
import '../../domain/entities/scan_mode.dart';
import '../../domain/entities/stored_scan.dart';
import '../../domain/lighting/flash_mode.dart';
import '../../domain/usecases/recognize_pages.dart';

/// A question about a dark shot that waits for the user (ADR-030).
enum LightPrompt {
  none,

  /// Single Page, One Click: the shot is dark; the dialog has three choices.
  /// Nothing of the shot is stored yet.
  singleShot,

  /// Multi Page, One Click, "Done": pages are flagged dark and have no
  /// decision; they must not be sent silently.
  summary,
}

enum ScanPhase {
  /// Checking the folder and starting the camera.
  starting,

  /// The storage folder is missing or no longer accessible.
  folderUnavailable,
  permissionDenied,
  cameraUnavailable,
  ready,
  capturing,
  saving,

  /// Writing to the folder failed. The pages are kept for a retry.
  saveFailed,

  /// The camera was released because the app went to the background.
  paused,
  saved,
}

class ScanState extends Equatable {
  const ScanState({
    this.phase = ScanPhase.starting,
    this.mode = ScanMode.single,
    this.pages = const <CapturedPage>[],
    this.result,
    this.captureFailed = false,
    this.saveCancelled = false,
    this.ocr,
    this.flashMode = FlashMode.off,
    this.hasFlash = false,
    this.lowLight = false,
    this.darkPages = const <String>[],
    this.lightPrompt = LightPrompt.none,
    this.darkBarPage,
    this.veryDarkPages = const <String>[],
    this.torchLit = false,
    this.torchIdleOff = false,
  });

  final ScanPhase phase;
  final ScanMode mode;
  final List<CapturedPage> pages;

  /// Set when [phase] is [ScanPhase.saved].
  final StoredScan? result;

  /// The last shot failed (shown as a message, the user can shoot again).
  final bool captureFailed;

  /// The user stopped the saving. Nothing was written (it was rolled back);
  /// in Multi the shots are still here, in Single the shot was dropped.
  final bool saveCancelled;

  /// The background reading of the pages, set when [phase] is
  /// [ScanPhase.saved]. The result screen owns it from then on.
  final OcrSession? ocr;

  /// The flash of the shots (Off, Auto, or On for this use only).
  final FlashMode flashMode;

  /// The phone has a flash: the button is shown only then.
  final bool hasFlash;

  /// The preview is dark ("Low light" mark next to the flash button).
  final bool lowLight;

  /// Shots measured dark that have no decision yet (the paths of the shots,
  /// which are also the keys of the pages of the reading).
  final List<String> darkPages;

  final LightPrompt lightPrompt;

  /// The last Multi shot was dark: the non-blocking bar offers a new shot.
  final String? darkBarPage;

  /// Of [darkPages], the shots so dark that the light correction is not
  /// expected to repair them (ADR-031): the warning advises a retake first.
  final List<String> veryDarkPages;

  /// The torch is really lit now (flash On, camera on screen).
  final bool torchLit;

  /// The torch was put out by the idle timeout and the choice went back to
  /// Auto: the screen shows its short message once.
  final bool torchIdleOff;

  /// A flagged page is so dark that a retake is advised before anything else.
  bool get darkNeedsRetake => darkPages.any(veryDarkPages.contains);

  bool get hasPages => pages.isNotEmpty;

  /// Taking photos is possible.
  bool get canCapture =>
      phase == ScanPhase.ready && lightPrompt == LightPrompt.none;

  /// The mode switch is locked once a multi-page scan has pages.
  bool get canChangeMode => phase == ScanPhase.ready && pages.isEmpty;

  bool get canFinish =>
      mode == ScanMode.multi && hasPages && phase == ScanPhase.ready;

  /// The pictures are being written to the folder and the user can stop it.
  bool get canCancelSaving => phase == ScanPhase.saving;

  /// Unsaved pages would be lost by leaving.
  bool get hasUnsavedPages => hasPages && phase != ScanPhase.saved;

  ScanState copyWith({
    ScanPhase? phase,
    ScanMode? mode,
    List<CapturedPage>? pages,
    StoredScan? result,
    bool? captureFailed,
    bool? saveCancelled,
    OcrSession? ocr,
    FlashMode? flashMode,
    bool? hasFlash,
    bool? lowLight,
    List<String>? darkPages,
    LightPrompt? lightPrompt,
    String? darkBarPage,
    bool clearDarkBar = false,
    List<String>? veryDarkPages,
    bool? torchLit,
    bool? torchIdleOff,
  }) {
    return ScanState(
      phase: phase ?? this.phase,
      mode: mode ?? this.mode,
      pages: pages ?? this.pages,
      result: result ?? this.result,
      captureFailed: captureFailed ?? this.captureFailed,
      saveCancelled: saveCancelled ?? this.saveCancelled,
      ocr: ocr ?? this.ocr,
      flashMode: flashMode ?? this.flashMode,
      hasFlash: hasFlash ?? this.hasFlash,
      lowLight: lowLight ?? this.lowLight,
      darkPages: darkPages ?? this.darkPages,
      lightPrompt: lightPrompt ?? this.lightPrompt,
      darkBarPage: clearDarkBar ? null : darkBarPage ?? this.darkBarPage,
      veryDarkPages: veryDarkPages ?? this.veryDarkPages,
      torchLit: torchLit ?? this.torchLit,
      torchIdleOff: torchIdleOff ?? this.torchIdleOff,
    );
  }

  @override
  List<Object?> get props => [
    phase,
    mode,
    pages,
    result,
    captureFailed,
    saveCancelled,
    ocr,
    flashMode,
    hasFlash,
    lowLight,
    darkPages,
    lightPrompt,
    darkBarPage,
    veryDarkPages,
    torchLit,
    torchIdleOff,
  ];
}
