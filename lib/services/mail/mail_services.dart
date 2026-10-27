import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/pdf_page_input.dart';
import '../../domain/mail/mail_auth.dart';
import '../../domain/mail/mail_cancellation.dart';
import '../../domain/mail/mail_message.dart';
import '../../domain/mail/mail_outcome.dart';
import '../../domain/mail/mail_provider.dart';
import '../../domain/ports/attachment_source.dart';
import '../../domain/mail/share_route.dart';
import '../../domain/ports/draft_sharer.dart';
import '../../domain/ports/link_opener.dart';
import '../../domain/ports/mail_app_finder.dart';
import '../../domain/ports/mail_credential_store.dart';
import '../../domain/ports/mail_sender.dart';
import 'android_mail_channels.dart';
import 'secure_mail_credential_store.dart';
import 'smtp_mail_sender.dart';

/// The platform adapters of the mail, created together like `PdfServices`.
class MailServices {
  const MailServices({
    required this.sender,
    required this.credentials,
    required this.attachments,
    required this.sharer,
    required this.appFinder,
    required this.links,
    this.providers = MailProviderRegistry.standard,
  });

  /// Nothing: the default of the container, so a test never opens a socket,
  /// touches the Keystore or calls a native channel by accident.
  const MailServices.unsupported()
    : sender = const UnsupportedMailSender(),
      credentials = const UnsupportedMailCredentialStore(),
      attachments = const UnsupportedAttachmentSource(),
      sharer = const UnsupportedDraftSharer(),
      appFinder = const UnsupportedMailAppFinder(),
      links = const UnsupportedLinkOpener(),
      providers = MailProviderRegistry.standard;

  final MailSender sender;
  final MailCredentialStore credentials;
  final AttachmentSource attachments;
  final DraftSharer sharer;
  final MailAppFinder appFinder;
  final LinkOpener links;

  /// `standard` in the app; the integration tests map a provider to a server
  /// on the PC (the `testLocal` provider exists only there).
  final MailProviderRegistry providers;
}

Future<MailServices> createPlatformMailServices({
  required AppLogger logger,
}) async {
  if (!Platform.isAndroid) return const MailServices.unsupported();
  final cache = await getTemporaryDirectory();
  return MailServices(
    sender: SmtpMailSender(logger: logger),
    credentials: SecureMailCredentialStore(
      store: const PluginSecureStringStore(),
      logger: logger,
    ),
    attachments: AndroidAttachmentSource(
      directory: Directory('${cache.path}${Platform.pathSeparator}mail_work'),
    ),
    sharer: AndroidDraftSharer(),
    appFinder: AndroidMailAppFinder(),
    links: AndroidLinkOpener(),
  );
}

class UnsupportedMailSender implements MailSender {
  const UnsupportedMailSender();

  @override
  Future<MailOutcome> send({
    required MailMessage message,
    required MailAuth auth,
    required MailProvider provider,
    MailCancellation? cancellation,
  }) async => const MailUnknown();

  @override
  Future<MailOutcome> checkConnection({
    required MailAuth auth,
    required MailProvider provider,
  }) async => const MailUnknown();
}

class UnsupportedMailCredentialStore implements MailCredentialStore {
  const UnsupportedMailCredentialStore();

  @override
  Future<StoredMailSecret?> read() async => null;

  @override
  Future<void> write(StoredMailSecret secret) async {}

  @override
  Future<void> delete() async {}
}

class UnsupportedAttachmentSource implements AttachmentSource {
  const UnsupportedAttachmentSource();

  @override
  Future<MailAttachment> prepare(StoredPdf pdf) {
    throw const AttachmentUnavailable();
  }

  @override
  Future<void> release(MailAttachment attachment) async {}

  @override
  Future<void> purgeAll() async {}
}

class UnsupportedDraftSharer implements DraftSharer {
  const UnsupportedDraftSharer();

  @override
  Future<DraftShareResult> share({
    required DraftShareRoute route,
    required List<String> to,
    required String subject,
    required String body,
    required String documentUri,
    required String mimeType,
  }) async => DraftShareResult.failed;
}

class UnsupportedMailAppFinder implements MailAppFinder {
  const UnsupportedMailAppFinder();

  @override
  Future<MailApps> find({String? providerPackage}) async => const MailApps();
}

class UnsupportedLinkOpener implements LinkOpener {
  const UnsupportedLinkOpener();

  @override
  Future<bool> open(String url) async => false;
}
