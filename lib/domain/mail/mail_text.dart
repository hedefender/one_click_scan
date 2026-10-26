import '../entities/app_language.dart';

/// The words of the message that leaves the phone. Fixed, neutral, and never
/// built from the document: the OCR text is not in the mail (ADR-020).
abstract final class MailText {
  /// The fixed start of every subject, so the user can make one rule in their
  /// mail app and forward all of them to a folder.
  static const subjectPrefix = 'One Click Scan';

  /// `One Click Scan - 2026-10-21_19-05-12`: the prefix and the name of the
  /// PDF without `.pdf` (a name is unique, and it is the name of the file).
  static String subject(String pdfFileName) {
    final lower = pdfFileName.toLowerCase();
    final stem = lower.endsWith('.pdf')
        ? pdfFileName.substring(0, pdfFileName.length - 4)
        : pdfFileName;
    return '$subjectPrefix - $stem';
  }

  /// One line, in the language of the app.
  static String body(AppLanguage language) {
    return switch (language) {
      AppLanguage.el => 'Σαρωμένο έγγραφο από το One Click Scan.',
      AppLanguage.en => 'Document scanned with One Click Scan.',
    };
  }
}
