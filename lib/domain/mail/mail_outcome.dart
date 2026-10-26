/// What happened to a message. Every way a send can end is a value, never an
/// exception to the UI, and none carries an address, a password or the text of
/// a server reply.
sealed class MailOutcome {
  const MailOutcome();
}

/// The server accepted the message. This is all that is known: it says
/// nothing about delivery.
final class MailSent extends MailOutcome {
  const MailSent();
}

/// The server did not accept the account or the password.
final class MailAuthFailed extends MailOutcome {
  const MailAuthFailed();
}

/// No connection, a timeout, a broken connection or a failed encryption.
final class MailNetworkError extends MailOutcome {
  const MailNetworkError();
}

/// The file is over the limit of the provider (checked before sending) or the
/// server refused the message as too big (reply 552).
final class MailTooLarge extends MailOutcome {
  const MailTooLarge();
}

/// The server answered with an error that is not one of the above; [code] is
/// the 3 digit reply code (0 when there is none).
final class MailRejected extends MailOutcome {
  const MailRejected(this.code);

  final int code;
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
