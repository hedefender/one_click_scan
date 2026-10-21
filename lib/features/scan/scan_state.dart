import 'package:equatable/equatable.dart';

import '../../domain/entities/captured_page.dart';
import '../../domain/entities/scan_mode.dart';
import '../../domain/entities/stored_scan.dart';

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
  });

  final ScanPhase phase;
  final ScanMode mode;
  final List<CapturedPage> pages;

  /// Set when [phase] is [ScanPhase.saved].
  final StoredScan? result;

  /// The last shot failed (shown as a message, the user can shoot again).
  final bool captureFailed;

  bool get hasPages => pages.isNotEmpty;

  /// Taking photos is possible.
  bool get canCapture => phase == ScanPhase.ready;

  /// The mode switch is locked once a multi-page scan has pages.
  bool get canChangeMode => phase == ScanPhase.ready && pages.isEmpty;

  bool get canFinish =>
      mode == ScanMode.multi && hasPages && phase == ScanPhase.ready;

  /// Unsaved pages would be lost by leaving.
  bool get hasUnsavedPages => hasPages && phase != ScanPhase.saved;

  ScanState copyWith({
    ScanPhase? phase,
    ScanMode? mode,
    List<CapturedPage>? pages,
    StoredScan? result,
    bool? captureFailed,
  }) {
    return ScanState(
      phase: phase ?? this.phase,
      mode: mode ?? this.mode,
      pages: pages ?? this.pages,
      result: result ?? this.result,
      captureFailed: captureFailed ?? this.captureFailed,
    );
  }

  @override
  List<Object?> get props => [phase, mode, pages, result, captureFailed];
}
