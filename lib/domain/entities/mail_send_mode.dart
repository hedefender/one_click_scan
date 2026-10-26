/// How a scan leaves the phone by e-mail (ADR-022).
enum MailSendMode {
  /// The app sends the message itself over SMTP, with the account of Settings.
  sendNow,

  /// The app opens the e-mail app with the recipient, the subject and the PDF
  /// filled in; the user presses send there.
  shareDraft,
}
