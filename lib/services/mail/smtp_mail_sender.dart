import 'dart:async';
import 'dart:isolate';

import '../../core/logging/app_logger.dart';
import '../../domain/mail/mail_auth.dart';
import '../../domain/mail/mail_cancellation.dart';
import '../../domain/mail/mail_message.dart';
import '../../domain/mail/mail_outcome.dart';
import '../../domain/mail/mail_provider.dart';
import '../../domain/ports/mail_sender.dart';
import 'smtp_worker.dart';

/// Sends through the SMTP server of the provider with the `mailer` package
/// (MIT; ADR-019 says why not `enough_mail`).
///
/// The work runs in its own isolate: the file is read and encoded off the UI
/// isolate, and a cancel kills the isolate, which closes the connection (a
/// message is delivered only if the server got the whole of it, so a cancel
/// never leaves half a message). `mailer` has no cancel of its own.
///
/// PRIVACY: nothing here logs an address, a password, a subject or the reply
/// of a server. The errors are turned into a [MailOutcome] inside the isolate
/// and only the kind of the error comes back.
class SmtpMailSender implements MailSender {
  SmtpMailSender({
    required this.logger,
    this.socketTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(minutes: 4),
  });

  final AppLogger logger;

  /// Longest wait for one reply of the server (connection, greeting, each
  /// command), the `timeout` of `mailer`.
  final Duration socketTimeout;

  /// Longest time for the whole send, whatever the size. A PDF of 14 MB on a
  /// slow mobile connection needs minutes.
  final Duration sendTimeout;

  @override
  Future<MailOutcome> send({
    required MailMessage message,
    required MailAuth auth,
    required MailProvider provider,
    MailCancellation? cancellation,
  }) {
    final credentials = _appPassword(auth);
    return _run(
      provider: provider,
      account: credentials.accountEmail,
      secret: credentials.secret,
      message: message,
      cancellation: cancellation,
      limit: sendTimeout,
    );
  }

  @override
  Future<MailOutcome> checkConnection({
    required MailAuth auth,
    required MailProvider provider,
  }) {
    final credentials = _appPassword(auth);
    return _run(
      provider: provider,
      account: credentials.accountEmail,
      secret: credentials.secret,
      limit: socketTimeout * 3,
    );
  }

  AppPasswordAuth _appPassword(MailAuth auth) {
    // `MailAuth` is sealed: an OAuth route adds its case here.
    return switch (auth) {
      AppPasswordAuth() => auth,
    };
  }

  Future<MailOutcome> _run({
    required MailProvider provider,
    required String account,
    required String secret,
    required Duration limit,
    MailMessage? message,
    MailCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) return const MailCancelled();
    final replies = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final result = Completer<MailOutcome>();
    Isolate? isolate;

    void finish(MailOutcome outcome) {
      if (!result.isCompleted) result.complete(outcome);
    }

    replies.listen((Object? reply) {
      if (reply is List && reply.isNotEmpty) {
        finish(outcomeFromReply(reply.cast<Object>()));
      } else {
        finish(const MailUnknown());
      }
    });
    errors.listen((_) => finish(const MailUnknown()));
    // The isolate ended without an answer.
    exits.listen(
      (_) => Future<void>.delayed(
        const Duration(milliseconds: 200),
        () => finish(const MailUnknown()),
      ),
    );
    unawaited(
      cancellation?.whenCancelled.then((_) => finish(const MailCancelled())),
    );
    final timer = Timer(limit, () => finish(const MailNetworkError()));
    try {
      isolate = await Isolate.spawn(
        smtpWorkerMain,
        SmtpJob(
          replyTo: replies.sendPort,
          host: provider.smtp.host,
          port: provider.smtp.port,
          security: provider.smtp.security,
          username: account,
          secret: secret,
          timeoutSeconds: socketTimeout.inSeconds,
          from: message?.from,
          to: message?.to ?? const [],
          subject: message?.subject ?? '',
          body: message?.body ?? '',
          attachments: [
            for (final a in message?.attachments ?? const <MailAttachment>[])
              [a.fileName, a.mimeType, a.path],
          ],
        ),
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );
      return await result.future;
    } catch (error, stackTrace) {
      logger.error(
        'Starting the mail worker failed',
        error.runtimeType,
        stackTrace,
      );
      return const MailUnknown();
    } finally {
      timer.cancel();
      isolate?.kill(priority: Isolate.immediate);
      replies.close();
      errors.close();
      exits.close();
    }
  }
}
