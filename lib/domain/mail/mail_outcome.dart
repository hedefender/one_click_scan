/// What happened to a message. Every way a send can end is a value, never an
/// exception to the UI, and none carries an address, a password or the text of
/// a server reply.
sealed class MailOutcome {
  const MailOutcome();

  /// The step of the send that failed, for the diagnostic line; null when the
  /// outcome has none (sent, cancelled, not configured, a check before any
  /// connection).
  MailStage? get stage => null;

  /// The 3 digit SMTP reply code, when the server gave one.
  int? get replyCode => null;
}

/// The steps of a send, in order. Part of the diagnostic line, which holds
/// this and a reply code and never an address, a host or the text of a reply.
enum MailStage { connection, tls, authentication, sending }

/// The server accepted the message. This is all that is known: it says
/// nothing about delivery.
final class MailSent extends MailOutcome {
  const MailSent();
}

/// The server did not accept the account or the password.
final class MailAuthFailed extends MailOutcome {
  const MailAuthFailed({this.code});

  /// The reply code of the refusal (535, 534, ...), when there is one.
  final int? code;

  @override
  MailStage get stage => MailStage.authentication;

  @override
  int? get replyCode => code;
}

/// No connection, a timeout, a broken connection or a failed encryption.
final class MailNetworkError extends MailOutcome {
  const MailNetworkError({this.failedStage = MailStage.connection});

  /// [MailStage.tls] when the encryption failed, otherwise the connection.
  final MailStage failedStage;

  @override
  MailStage get stage => failedStage;
}

/// The file is over the limit of the provider (checked before sending) or the
/// server refused the message as too big (reply 552).
final class MailTooLarge extends MailOutcome {
  const MailTooLarge({this.fromServer = false});

  /// True when the server said so (552); false for the check before sending.
  final bool fromServer;

  @override
  MailStage? get stage => fromServer ? MailStage.sending : null;

  @override
  int? get replyCode => fromServer ? 552 : null;
}

/// The server answered with an error that is not one of the above; [code] is
/// the 3 digit reply code (0 when there is none).
final class MailRejected extends MailOutcome {
  const MailRejected(this.code);

  final int code;

  @override
  MailStage get stage => MailStage.sending;

  @override
  int? get replyCode => code == 0 ? null : code;
}

/// The user stopped the send.
final class MailCancelled extends MailOutcome {
  const MailCancelled();
}

final class MailUnknown extends MailOutcome {
  const MailUnknown();
}

enum MailNotConfiguredReason { provider, account, destination, password }

/// Added to the list of the request: the settings are not complete, so
/// nothing was tried. The screen sends the user to Settings.
final class MailNotConfigured extends MailOutcome {
  const MailNotConfigured(this.reason);

  final MailNotConfiguredReason reason;
}
