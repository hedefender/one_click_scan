import 'mail_provider.dart';

/// Whether a PDF fits in a message the provider takes.
///
/// A file travels as base64 inside MIME: 3 bytes become 4 characters and a
/// line break follows every 76, so the message is about 1.37 times the file
/// (`MAIL_PROVIDERS.md`). The limit of a provider is on the message, so the
/// biggest PDF is the limit divided by that, after the room for the headers
/// and the body.
abstract final class MailSizePolicy {
  /// Message size over file size: 4/3 for base64 and 78/76 for the line breaks.
  static const double encodingFactor = 4 / 3 * 78 / 76;

  /// Room kept for the headers, the body and the MIME frame.
  static const int headroomBytes = 64 * 1024;

  /// The biggest file the app sends through [provider].
  static int maxAttachmentBytes(MailProvider provider) {
    final room = provider.maxMessageBytes - headroomBytes;
    return room <= 0 ? 0 : (room / encodingFactor).floor();
  }

  /// The size of the message that carries a file of [fileBytes].
  static int encodedMessageBytes(int fileBytes) =>
      (fileBytes * encodingFactor).ceil() + headroomBytes;

  static bool fits(MailProvider provider, int fileBytes) =>
      fileBytes <= maxAttachmentBytes(provider);
}
