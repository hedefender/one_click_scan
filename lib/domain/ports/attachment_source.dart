import '../entities/pdf_page_input.dart';
import '../mail/mail_message.dart';

/// Gives a stored PDF as a local file the mail sender can read (the PDF lives in
/// the user's folder behind a document URI, which only native code can read).
abstract interface class AttachmentSource {
  /// Copies [pdf] into the app cache. Throws [AttachmentUnavailable] when the
  /// file is gone or cannot be read.
  Future<MailAttachment> prepare(StoredPdf pdf);

  /// Deletes the copy made by [prepare]. Never throws.
  Future<void> release(MailAttachment attachment);

  /// Deletes every copy left by a run that was killed half way (start-up).
  Future<void> purgeAll();
}

class AttachmentUnavailable implements Exception {
  const AttachmentUnavailable();

  @override
  String toString() => 'AttachmentUnavailable';
}
