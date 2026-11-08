import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/guide/guide_view.dart';
import '../../presentation/l10n/app_strings.dart';
import 'help_keys.dart';

/// The last page of the wizard, shown again from Help. It reads the same
/// sections as the wizard and asks for no setting.
class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      key: HelpKeys.guidePage,
      appBar: AppBar(title: Text(strings.guideTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.guideIntro, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 24),
                    GuideSectionsView(
                      sections: [
                        for (final section in strings.guideSections)
                          if (section.inWizard) section,
                      ],
                    ),
                    Text(
                      strings.guideLastLine,
                      key: GuideKeys.lastLine,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: HelpKeys.guideClose,
                  onPressed: () => context.pop(),
                  child: Text(strings.guideClose),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
