import 'dart:async';
import 'dart:io';

import 'package:mailer/mailer.dart';

import '../../domain/mail/mail_outcome.dart';

/// Turns what `mailer` throws into a [MailOutcome]. Pure, so every case is a
/// unit test. Nothing of the error text is kept except a 3 digit reply code:
/// the text of a server reply can contain the address of the user.
MailOutcome outcomeForSmtpError(Object error) {
  if (error is SmtpClientAuthenticationException) {
    return MailAuthFailed(code: smtpReplyCode(error.message));
  }
  if (error is SmtpClientCommunicationException) {
    final code = smtpReplyCode(error.message);
    if (code == null) return const MailNetworkError();
    return outcomeForReplyCode(code);
  }
  if (error is HandshakeException ||
      error is TlsException ||
      error is SmtpUnsecureException) {
    return const MailNetworkError(failedStage: MailStage.tls);
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is SmtpNoGreetingException) {
    return const MailNetworkError();
  }
  return const MailUnknown();
}

/// 552 is "too much data"; 530, 534, 535 and 454 are about the account or the
/// way it signs in; everything else is a rejection that carries its code.
MailOutcome outcomeForReplyCode(int code) {
  switch (code) {
    case 552:
      return const MailTooLarge(fromServer: true);
    case 530:
    case 534:
    case 535:
    case 454:
      return MailAuthFailed(code: code);
    default:
      return MailRejected(code);
  }
}

final RegExp _replyLine = RegExp(r'<\s*(\d{3})[ -]');

/// The first server reply code in a `mailer` message
/// (`Response from server: < 552 ...`), or null.
int? smtpReplyCode(String message) {
  final match = _replyLine.firstMatch(message);
  return match == null ? null : int.parse(match.group(1)!);
}
