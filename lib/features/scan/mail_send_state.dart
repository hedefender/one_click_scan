import 'package:equatable/equatable.dart';

import '../../domain/entities/mail_provider_id.dart';
import '../../domain/entities/mail_send_mode.dart';
import '../../domain/mail/mail_outcome.dart';
import '../../domain/ports/draft_sharer.dart';

enum MailPhase {
  /// Nothing sent yet.
  idle,
  sending,

  /// The SMTP server accepted the message (nothing is known about delivery).
  sent,

  /// The send ended without the server accepting the message; [MailSendState.outcome]
  /// says why.
  failed,
}

class MailSendState extends Equatable {
  const MailSendState({
    this.phase = MailPhase.idle,
    this.mode = MailSendMode.sendNow,
    this.outcome,
    this.draft,
  });

  final MailPhase phase;

  /// What the main button does (read from Settings each time).
  final MailSendMode mode;

  /// Set when [phase] is [MailPhase.failed].
  final MailOutcome? outcome;

  /// The last try to open the e-mail app (null before the first).
  final DraftShareResult? draft;

  bool get busy => phase == MailPhase.sending;

  /// The one-tap way to the backup route: the sign-in was refused, or the
  /// provider is Outlook (no app password for SMTP), and the mode is still
  /// `sendNow`.
  bool offersFallback(MailProviderId? provider) {
    if (mode != MailSendMode.sendNow || phase != MailPhase.failed) return false;
    if (outcome is MailNotConfigured) return false;
    return outcome is MailAuthFailed || provider == MailProviderId.outlook;
  }

  /// The settings are incomplete: the screen leads to Settings.
  bool get needsSettings => outcome is MailNotConfigured;

  MailSendState copyWith({
    MailPhase? phase,
    MailSendMode? mode,
    MailOutcome? outcome,
    DraftShareResult? draft,
    bool clearOutcome = false,
    bool clearDraft = false,
  }) {
    return MailSendState(
      phase: phase ?? this.phase,
      mode: mode ?? this.mode,
      outcome: clearOutcome ? null : outcome ?? this.outcome,
      draft: clearDraft ? null : draft ?? this.draft,
    );
  }

  @override
  List<Object?> get props => [phase, mode, outcome, draft];
}
