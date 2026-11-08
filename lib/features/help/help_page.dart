import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import '../../presentation/guide/guide_view.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../presentation/l10n/guide_section.dart';
import 'help_keys.dart';

/// Help (Settings): the same text as the last page of the wizard, in more
/// detail and by section, plus the two sections that are only here: the e-mail
/// steps and what the app does not cover. "See the guide again" shows the last
/// page of the wizard without asking for any setting (ADR-032).
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  void _openMailSettings(BuildContext context) {
    // Help is opened from Settings: going back is going to the e-mail section.
    if (context.canPop()) {
      context.pop();
    } else {
      context.push(RoutePaths.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      key: HelpKeys.page,
      appBar: AppBar(title: Text(strings.helpTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            OutlinedButton.icon(
              key: HelpKeys.seeGuideAgain,
              onPressed: () => context.push(RoutePaths.helpGuide),
              icon: const Icon(Icons.lightbulb_outline),
              label: Text(strings.helpSeeGuideAgain),
            ),
            const SizedBox(height: 24),
            GuideSectionsView(
              sections: strings.guideSections,
              detailed: true,
              extraFor: (section) => section.id == GuideSectionId.email
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        key: HelpKeys.openMailSettings,
                        onPressed: () => _openMailSettings(context),
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(strings.helpOpenMailSettings),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
