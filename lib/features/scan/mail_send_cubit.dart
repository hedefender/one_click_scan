import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/mail_send_mode.dart';
import '../../domain/entities/pdf_page_input.dart';
import '../../domain/mail/mail_cancellation.dart';
import '../../domain/mail/mail_outcome.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/send_scan_pdf.dart';
import '../../domain/usecases/update_settings.dart';
import 'mail_send_state.dart';

/// Sends the stored PDF by e-mail when the user taps the button (Phase 4: by
/// hand; no automatic send, no automatic retry).
///
/// Settings are read at each tap, so an account set up in Settings a moment ago
/// is used. A failure is a state, never a crash, and nothing here holds an
/// address or a password: the use cases do, for the length of a call.
class MailSendCubit extends Cubit<MailSendState> {
  MailSendCubit({
    required this._loadSettings,
    required this._updateSettings,
    required this._send,
    required this._share,
    required this._logger,
  }) : super(const MailSendState());

  final LoadSettings _loadSettings;
  final UpdateSettings _updateSettings;
  final SendScanPdf _send;
  final ShareScanPdfDraft _share;
  final AppLogger _logger;

  MailCancellation? _cancellation;
  StoredPdf? _pdf;

  /// The PDF this cubit sends. The cubit exists from the start of the result
  /// screen (so the screen can lock leaving while a send runs); the PDF is known
  /// when it is stored.
  Future<void> attach(StoredPdf pdf) async {
    _pdf = pdf;
    await start();
  }

  /// Reads the mode of Settings, so the button says the right thing.
  Future<void> start() async {
    final settings = await _loadSettings();
    if (isClosed) return;
    emit(state.copyWith(mode: settings.mailSendMode));
  }

  /// The main button: sends over SMTP, or opens the e-mail app, as Settings say.
  Future<void> send() async {
    final pdf = _pdf;
    if (pdf == null || state.busy) return;
    final settings = await _loadSettings();
    if (isClosed) return;
    if (settings.mailSendMode == MailSendMode.shareDraft) {
      emit(state.copyWith(mode: MailSendMode.shareDraft));
      await openMailApp();
      return;
    }
    final cancellation = MailCancellation();
    _cancellation = cancellation;
    emit(
      MailSendState(
        phase: MailPhase.sending,
        mode: settings.mailSendMode,
        draft: state.draft,
      ),
    );
    final MailOutcome outcome;
    try {
      outcome = await _send(
        settings: settings,
        pdf: pdf,
        cancellation: cancellation,
      );
    } catch (error, stackTrace) {
      _logger.error(
        'Sending the mail failed unexpectedly',
        error.runtimeType,
        stackTrace,
      );
      _finish(const MailUnknown());
      return;
    } finally {
      _cancellation = null;
    }
    _finish(outcome);
  }

  /// "Use the backup way to send": sets the mode to `shareDraft` with one tap
  /// (the same setting as in Settings) and leaves the failure behind, so the
  /// main button now opens the e-mail app.
  Future<void> useShareMode() async {
    if (state.busy) return;
    await _updateSettings(
      (current) => current.copyWith(mailSendMode: MailSendMode.shareDraft),
    );
    if (isClosed) return;
    emit(
      state.copyWith(
        phase: MailPhase.idle,
        mode: MailSendMode.shareDraft,
        clearOutcome: true,
      ),
    );
  }

  /// Stops a send in progress.
  void cancel() => _cancellation?.cancel();

  /// "Open in the e-mail app": the way out of a failed send, and the main
  /// button in the `shareDraft` mode. The user presses send there.
  Future<void> openMailApp() async {
    final pdf = _pdf;
    if (pdf == null || state.busy) return;
    final settings = await _loadSettings();
    final result = await _share(settings: settings, pdf: pdf);
    if (isClosed) return;
    emit(state.copyWith(draft: result));
  }

  void _finish(MailOutcome outcome) {
    if (isClosed) return;
    switch (outcome) {
      case MailSent():
        emit(
          state.copyWith(
            phase: MailPhase.sent,
            clearOutcome: true,
            clearDraft: true,
          ),
        );
      case MailCancelled():
        emit(state.copyWith(phase: MailPhase.idle, clearOutcome: true));
      default:
        emit(state.copyWith(phase: MailPhase.failed, outcome: outcome));
    }
  }

  @override
  Future<void> close() {
    // Leaving the screen ends a send that is still running.
    _cancellation?.cancel();
    return super.close();
  }
}
