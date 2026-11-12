import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/config/about_config.dart';
import '../../core/config/app_config.dart';
import '../../domain/ports/app_info_source.dart';
import '../../domain/ports/feedback_composer.dart';
import '../../domain/ports/link_opener.dart';
import '../../presentation/l10n/app_strings.dart';
import 'about_keys.dart';

/// About (Settings): name, version, a one-line description, the copyright, the
/// link to the repository and the privacy note. The feedback button is shown
/// only when [feedbackRecipient] is not empty (`FeedbackConfig.recipient`).
class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    required this.appName,
    required this.infoSource,
    required this.links,
    required this.feedback,
    required this.feedbackRecipient,
  });

  factory AboutPage.fromContainer(
    GetIt sl, {
    required String feedbackRecipient,
  }) {
    return AboutPage(
      appName: sl<AppConfig>().appName,
      infoSource: sl<AppInfoSource>(),
      links: sl<LinkOpener>(),
      feedback: sl<FeedbackComposer>(),
      feedbackRecipient: feedbackRecipient,
    );
  }

  final String appName;
  final AppInfoSource infoSource;
  final LinkOpener links;
  final FeedbackComposer feedback;
  final String feedbackRecipient;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  AppInfo? _info;

  @override
  void initState() {
    super.initState();
    widget.infoSource.read().then((info) {
      if (!mounted) return;
      setState(() => _info = info);
    });
  }

  Future<void> _openRepo(AppStrings strings) async {
    final opened = await widget.links.open(AboutConfig.repositoryUrl);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.aboutOpenFailed)));
    }
  }

  Future<void> _sendFeedback(AppStrings strings) async {
    final info = _info;
    final language = Localizations.localeOf(context).languageCode;
    final opened = await widget.feedback.compose(
      to: widget.feedbackRecipient,
      subject: strings.feedbackSubject(
        widget.appName,
        info?.versionLabel ?? '',
      ),
      body: strings.feedbackBody(
        version: info?.versionLabel ?? '',
        androidRelease: info?.androidRelease ?? '',
        language: language,
      ),
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.feedbackFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final info = _info;
    return Scaffold(
      key: AboutKeys.page,
      appBar: AppBar(title: Text(strings.aboutTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.appName,
              key: AboutKeys.name,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            if (info != null)
              Text(
                strings.aboutVersion(info.versionName, info.buildNumber),
                key: AboutKeys.version,
                style: theme.textTheme.bodyMedium,
              ),
            const SizedBox(height: 12),
            Text(strings.aboutDescription, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            Text(AboutConfig.copyright, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            Text(strings.aboutRepoTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            SelectableText(
              AboutConfig.repositoryUrl,
              key: AboutKeys.repoLink,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: AboutKeys.openRepo,
                onPressed: () => _openRepo(strings),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(strings.aboutOpenRepo),
              ),
            ),
            const SizedBox(height: 24),
            Text(strings.aboutPrivacyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Column(
              key: AboutKeys.privacy,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in strings.aboutPrivacyLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(line, style: theme.textTheme.bodyMedium),
                  ),
              ],
            ),
            if (widget.feedbackRecipient.isNotEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: AboutKeys.feedback,
                onPressed: () => _sendFeedback(strings),
                icon: const Icon(Icons.mail_outline_rounded),
                label: Text(strings.feedbackButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
