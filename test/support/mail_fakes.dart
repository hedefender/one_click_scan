import 'dart:async';

import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/mail/mail_auth.dart';
import 'package:one_click_scan/domain/mail/mail_cancellation.dart';
import 'package:one_click_scan/domain/mail/mail_message.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/ports/attachment_source.dart';
import 'package:one_click_scan/domain/ports/draft_sharer.dart';
import 'package:one_click_scan/domain/ports/mail_credential_store.dart';
import 'package:one_click_scan/domain/ports/mail_sender.dart';
import 'package:one_click_scan/services/mail/mail_services.dart';
import 'package:one_click_scan/services/mail/secure_mail_credential_store.dart';

/// Invented values. Nothing real is ever used in a test: addresses are
/// `example.test` / `example.com`, passwords are made up, and [canarySecret]
/// is the one the tests look for in logs, messages and `toString`.
const canarySecret = 'canary-Secret-7f3a91';
const testAccount = 'user@example.test';
const testDestination = 'inbox@example.com';

/// The `testLocal` provider: a plain connection (no TLS) to a server on this
/// computer. It exists only in tests (a test checks that the app's registry has
/// no such provider).
MailProvider testLocalProvider({
  required int port,
  String host = '127.0.0.1',
  int maxMessageBytes = 25000000,
}) {
  return MailProvider(
    id: 'testLocal',
    smtp: SmtpEndpoint(host: host, port: port, security: SmtpSecurity.plain),
    authKinds: const {MailAuthKind.appPassword},
    appPasswordSupport: AppPasswordSupport.supported,
    maxMessageBytes: maxMessageBytes,
  );
}

/// A logger that keeps the error too, which `RecordingLogger` does not: a test
/// that looks for a secret in the logs must see everything that was logged.
class CapturingLogger implements AppLogger {
  final List<String> lines = [];

  @override
  void debug(String message) => lines.add('debug: $message');

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    lines.add('error: $message | $error | $stackTrace');
  }

  String get all => lines.join('\n');
}

class FakeMailSender implements MailSender {
  MailOutcome outcome = const MailSent();

  /// Thrown by [send] when set (the port promises not to, the use case has a
  /// net under it).
  Object? throwOnSend;

  /// When set, [send] waits for it (to test cancel and the busy state).
  Completer<MailOutcome>? hold;

  /// Thrown by [checkConnection] when set.
  Object? throwOnCheck;

  /// When set, [checkConnection] waits for it.
  Completer<void>? holdCheck;

  final List<MailMessage> sent = [];
  final List<AppPasswordAuth> auths = [];
  final List<MailProvider> providers = [];
  final List<String> readAttachments = [];
  int checks = 0;

  @override
  Future<MailOutcome> send({
    required MailMessage message,
    required MailAuth auth,
    required MailProvider provider,
    MailCancellation? cancellation,
  }) async {
    sent.add(message);
    auths.add(auth as AppPasswordAuth);
    providers.add(provider);
    readAttachments.addAll(message.attachments.map((a) => a.path));
    final failure = throwOnSend;
    if (failure != null) throw failure;
    final waiting = hold;
    if (waiting != null) {
      return Future.any([
        waiting.future,
        if (cancellation != null)
          cancellation.whenCancelled.then<MailOutcome>(
            (_) => const MailCancelled(),
          ),
      ]);
    }
    return outcome;
  }

  @override
  Future<MailOutcome> checkConnection({
    required MailAuth auth,
    required MailProvider provider,
  }) async {
    checks++;
    auths.add(auth as AppPasswordAuth);
    providers.add(provider);
    final failure = throwOnCheck;
    if (failure != null) throw failure;
    await holdCheck?.future;
    return outcome;
  }
}

class FakeMailCredentialStore implements MailCredentialStore {
  StoredMailSecret? stored;
  Object? failWrite;
  Object? failDelete;
  int reads = 0;

  @override
  Future<StoredMailSecret?> read() async {
    reads++;
    return stored;
  }

  @override
  Future<void> write(StoredMailSecret secret) async {
    final failure = failWrite;
    if (failure != null) throw failure;
    stored = secret;
  }

  @override
  Future<void> delete() async {
    final failure = failDelete;
    if (failure != null) throw failure;
    stored = null;
  }
}

class FakeAttachmentSource implements AttachmentSource {
  bool unavailable = false;
  final List<StoredPdf> prepared = [];
  final List<MailAttachment> released = [];
  int purges = 0;

  @override
  Future<MailAttachment> prepare(StoredPdf pdf) async {
    if (unavailable) throw const AttachmentUnavailable();
    prepared.add(pdf);
    return MailAttachment(
      fileName: pdf.fileName,
      mimeType: 'application/pdf',
      path: 'mail_work/${pdf.fileName}',
    );
  }

  @override
  Future<void> release(MailAttachment attachment) async =>
      released.add(attachment);

  @override
  Future<void> purgeAll() async => purges++;
}

class FakeDraftSharer implements DraftSharer {
  DraftShareResult result = DraftShareResult.opened;
  final List<Map<String, Object>> shared = [];

  @override
  Future<DraftShareResult> share({
    required List<String> to,
    required String subject,
    required String body,
    required String documentUri,
    required String mimeType,
  }) async {
    shared.add({
      'to': to,
      'subject': subject,
      'body': body,
      'uri': documentUri,
      'mimeType': mimeType,
    });
    return result;
  }
}

/// Fake mail adapters as a bundle for `buildTestContainer`.
class MailTestRig {
  final sender = FakeMailSender();
  final credentials = FakeMailCredentialStore();
  final attachments = FakeAttachmentSource();
  final sharer = FakeDraftSharer();

  MailServices get services => MailServices(
    sender: sender,
    credentials: credentials,
    attachments: attachments,
    sharer: sharer,
  );

  /// A stored password for [provider] and [account] (the one of the settings
  /// the tests use).
  void storePassword({
    MailProviderId provider = MailProviderId.gmail,
    String account = testAccount,
    String secret = canarySecret,
  }) {
    credentials.stored = StoredMailSecret(
      provider: provider,
      accountEmail: account,
      secret: secret,
    );
  }
}

/// A [SecureStringStore] in memory.
class InMemorySecureStringStore implements SecureStringStore {
  final Map<String, String> values = {};
  Object? failRead;

  @override
  Future<String?> read(String key) async {
    final failure = failRead;
    if (failure != null) throw failure;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
