import '../../core/logging/app_logger.dart';
import '../../shared/validators/email_validator.dart';
import '../entities/app_settings.dart';
import '../entities/mail_provider_id.dart';
import '../entities/pdf_page_input.dart';
import '../mail/mail_auth.dart';
import '../mail/mail_cancellation.dart';
import '../mail/mail_message.dart';
import '../mail/mail_outcome.dart';
import '../mail/mail_provider.dart';
import '../mail/mail_size_policy.dart';
import '../mail/mail_text.dart';
import '../ports/attachment_source.dart';
import '../ports/draft_sharer.dart';
import '../ports/mail_credential_store.dart';
import '../ports/mail_sender.dart';

/// Sends the PDF of a scan with the account of Settings (the `sendNow` mode).
///
/// Order: settings complete? password stored for this provider and account?
/// PDF small enough for the provider (before anything is read or sent)? then
/// the PDF is copied to the cache, sent, and the copy deleted in every case.
/// The message is fixed: the subject `One Click Scan - <name of the PDF>`, one
/// neutral line, the PDF; never any text of the document (ADR-020). Never
/// throws; the outcome says what happened.
class SendScanPdf {
  const SendScanPdf({
    required this.sender,
    required this.attachments,
    required this.credentials,
    required this.providers,
    required this.logger,
  });

  final MailSender sender;
  final AttachmentSource attachments;
  final MailCredentialStore credentials;
  final MailProviderRegistry providers;
  final AppLogger logger;

  Future<MailOutcome> call({
    required AppSettings settings,
    required StoredPdf pdf,
    MailCancellation? cancellation,
  }) async {
    final providerId = settings.mailProvider;
    final account = settings.senderAccount?.trim();
    final destination = settings.effectiveDestination?.trim();
    if (providerId == null) {
      return const MailNotConfigured(MailNotConfiguredReason.provider);
    }
    if (!isValidEmail(account)) {
      return const MailNotConfigured(MailNotConfiguredReason.account);
    }
    if (!isValidEmail(destination)) {
      return const MailNotConfigured(MailNotConfiguredReason.destination);
    }
    final stored = await credentials.read();
    if (stored == null || !stored.belongsTo(providerId, account)) {
      return const MailNotConfigured(MailNotConfiguredReason.password);
    }
    final provider = providers.resolve(providerId);
    if (!MailSizePolicy.fits(provider, pdf.byteSize)) {
      return const MailTooLarge();
    }
    if (cancellation?.isCancelled ?? false) return const MailCancelled();

    final MailAttachment attachment;
    try {
      attachment = await attachments.prepare(pdf);
    } on AttachmentUnavailable {
      logger.error('The stored PDF could not be read for the mail');
      return const MailUnknown();
    }
    try {
      return await sender.send(
        message: MailMessage(
          from: account!,
          to: [destination!],
          subject: MailText.subject(pdf.fileName),
          body: MailText.body(settings.language),
          attachments: [attachment],
        ),
        auth: AppPasswordAuth(accountEmail: account, secret: stored.secret),
        provider: provider,
        cancellation: cancellation,
      );
    } catch (error, stackTrace) {
      // The port promises an outcome; this is only a net under it.
      logger.error('The mail sender threw', error.runtimeType, stackTrace);
      return const MailUnknown();
    } finally {
      await attachments.release(attachment);
    }
  }
}

/// Opens the e-mail app with the message filled in (the `shareDraft` mode, and
/// the way out when a send failed). The user presses send there; nothing is
/// known about what happens next.
class ShareScanPdfDraft {
  const ShareScanPdfDraft({required this.sharer});

  final DraftSharer sharer;

  Future<DraftShareResult> call({
    required AppSettings settings,
    required StoredPdf pdf,
  }) {
    final destination = settings.effectiveDestination?.trim();
    return sharer.share(
      to: isValidEmail(destination) ? [destination!] : const [],
      subject: MailText.subject(pdf.fileName),
      body: MailText.body(settings.language),
      documentUri: pdf.uri,
      mimeType: 'application/pdf',
    );
  }
}

/// Connects and signs in with the account of the screen, sending nothing.
class CheckMailConnection {
  const CheckMailConnection({required this.sender, required this.providers});

  final MailSender sender;
  final MailProviderRegistry providers;

  /// [provider] and [accountEmail] are the ones on the screen, which may not
  /// be saved yet.
  Future<MailOutcome> call({
    required MailProviderId? provider,
    required String accountEmail,
    required String secret,
  }) async {
    if (provider == null) {
      return const MailNotConfigured(MailNotConfiguredReason.provider);
    }
    return sender.checkConnection(
      auth: AppPasswordAuth(accountEmail: accountEmail, secret: secret),
      provider: providers.resolve(provider),
    );
  }
}
