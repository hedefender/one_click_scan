/// What happened when the user asked to open the e-mail app.
enum DraftShareResult {
  /// The e-mail app (or the chooser) was opened. The user presses send there.
  opened,

  /// No installed app takes an e-mail with an attachment.
  noApp,

  /// The PDF could not be handed over (it is gone, or access was lost).
  failed,
}

/// Opens an e-mail app with the recipient, the subject, the text and the PDF
/// filled in (`ACTION_SEND`). The app cannot know whether the user sends it.
abstract interface class DraftSharer {
  /// [documentUri] is the document URI of the stored PDF; the e-mail app gets a
  /// temporary read grant for it. Never throws.
  Future<DraftShareResult> share({
    required List<String> to,
    required String subject,
    required String body,
    required String documentUri,
    required String mimeType,
  });
}
