import '../mail/mail_auth.dart';
import '../mail/mail_cancellation.dart';
import '../mail/mail_message.dart';
import '../mail/mail_outcome.dart';
import '../mail/mail_provider.dart';

/// Sends a message through a provider. Never throws: every end is a
/// [MailOutcome].
abstract interface class MailSender {
  /// Sends [message] and waits for the server to accept it. [cancellation]
  /// stops the send ([MailCancelled]).
  Future<MailOutcome> send({
    required MailMessage message,
    required MailAuth auth,
    required MailProvider provider,
    MailCancellation? cancellation,
  });

  /// Connects and signs in, sends NOTHING. [MailSent] means "the server
  /// accepted the account"; the other outcomes say why not.
  Future<MailOutcome> checkConnection({
    required MailAuth auth,
    required MailProvider provider,
  });
}
