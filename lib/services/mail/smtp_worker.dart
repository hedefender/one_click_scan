import 'dart:io';
import 'dart:isolate';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../../domain/mail/mail_outcome.dart';
import '../../domain/mail/mail_provider.dart';
import 'smtp_error_mapping.dart';

/// Everything the isolate needs, as plain values (it crosses `Isolate.spawn`).
/// The secret lives in this object only for the length of one send.
class SmtpJob {
  const SmtpJob({
    required this.replyTo,
    required this.host,
    required this.port,
    required this.security,
    required this.username,
    required this.secret,
    required this.timeoutSeconds,
    this.from,
    this.to = const [],
    this.subject = '',
    this.body = '',
    this.attachments = const [],
  });

  final SendPort replyTo;
  final String host;
  final int port;
  final SmtpSecurity security;
  final String username;
  final String secret;
  final int timeoutSeconds;

  /// Null for a connection check, which sends nothing.
  final String? from;
  final List<String> to;
  final String subject;
  final String body;

  /// `[fileName, mimeType, path]` per attachment.
  final List<List<String>> attachments;
}

/// What the isolate answers: a tag, a reply code (0 when none) and the index of
/// the [MailStage] (-1 when none).
typedef SmtpReply = List<Object>;

const _tagSent = 'sent';
const _tagAuth = 'auth';
const _tagNetwork = 'network';
const _tagTooLarge = 'tooLarge';
const _tagRejected = 'rejected';
const _tagUnknown = 'unknown';

MailOutcome outcomeFromReply(SmtpReply reply) {
  final code = reply[1] as int;
  final stageIndex = reply.length > 2 ? reply[2] as int : -1;
  return switch (reply.first) {
    _tagSent => const MailSent(),
    _tagAuth => MailAuthFailed(code: code == 0 ? null : code),
    _tagNetwork => MailNetworkError(
      failedStage: stageIndex == MailStage.tls.index
          ? MailStage.tls
          : MailStage.connection,
    ),
    _tagTooLarge => MailTooLarge(fromServer: code != 0),
    _tagRejected => MailRejected(code),
    _ => const MailUnknown(),
  };
}

SmtpReply _replyFor(MailOutcome outcome) {
  final stage = outcome.stage?.index ?? -1;
  return switch (outcome) {
    MailSent() => [_tagSent, 0, -1],
    MailAuthFailed(:final code) => [_tagAuth, code ?? 0, stage],
    MailNetworkError() => [_tagNetwork, 0, stage],
    MailTooLarge(:final fromServer) => [
      _tagTooLarge,
      fromServer ? 552 : 0,
      stage,
    ],
    MailRejected(:final code) => [_tagRejected, code, stage],
    _ => [_tagUnknown, 0, -1],
  };
}

/// Entry point of the SMTP isolate. Runs one job and answers once. Killing
/// the isolate (the user cancelled) closes its sockets with it.
Future<void> smtpWorkerMain(SmtpJob job) async {
  try {
    final server = SmtpServer(
      job.host,
      port: job.port,
      ssl: job.security == SmtpSecurity.implicitTls,
      allowInsecure: job.security == SmtpSecurity.plain,
      username: job.username,
      password: job.secret,
    );
    final timeout = Duration(seconds: job.timeoutSeconds);
    final from = job.from;
    if (from == null) {
      await checkCredentials(server, timeout: timeout);
    } else {
      final message = Message()
        ..from = Address(from)
        ..recipients.addAll(job.to)
        ..subject = job.subject
        ..text = job.body
        ..attachments.addAll([
          for (final a in job.attachments)
            FileAttachment(File(a[2]), fileName: a[0], contentType: a[1]),
        ]);
      await send(message, server, timeout: timeout);
    }
    job.replyTo.send(_replyFor(const MailSent()));
  } catch (error) {
    // Only the kind of the error leaves this isolate, never its text.
    job.replyTo.send(_replyFor(outcomeForSmtpError(error)));
  }
}
