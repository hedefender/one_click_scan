import '../../domain/entities/mail_provider_id.dart';
import '../../domain/mail/mail_provider.dart';
import '../../domain/mail/mail_size_policy.dart';

/// One section of the guide (ADR-032). The text of a section lives in ONE
/// place, `AppStrings.guideSections`, and every screen that shows the guide
/// reads it from there, so the wizard page, the Help screen and the first-open
/// hint of Multi Page can never say different things.
class GuideSection {
  const GuideSection({
    required this.id,
    required this.title,
    required this.lines,
    this.details = const <String>[],
    this.inWizard = false,
  });

  final GuideSectionId id;
  final String title;

  /// The short, scannable lines. The last page of the wizard shows these only.
  final List<String> lines;

  /// More detail. Only the Help screen shows it, after [lines].
  final List<String> details;

  /// The last page of the wizard shows this section. Sections that are not in
  /// the wizard (the e-mail steps, what the app does not cover) are Help only.
  final bool inWizard;
}

enum GuideSectionId {
  mode,
  flash,
  lowLight,
  tips,
  multi,
  email,
  cancel,
  privacy,
  notCovered,
}

/// The biggest PDF a provider takes, in whole megabytes rounded down, for the
/// texts of the guide. It reads the same limit the send check uses, so the
/// guide cannot disagree with the app.
String providerMegabytes(MailProviderId id) {
  final bytes = MailSizePolicy.maxAttachmentBytes(
    MailProviderRegistry.standard.resolve(id),
  );
  return (bytes / 1e6).floor().toString();
}
