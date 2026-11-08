import 'package:flutter/material.dart';

import '../l10n/guide_section.dart';

/// Widget keys used by widget and integration tests.
abstract final class GuideKeys {
  static Key section(GuideSectionId id) => Key('guide.section.${id.name}');
  static const lastLine = Key('guide.lastLine');
  static const view = Key('guide.view');
}

/// The sections of the guide, one under the other. The wizard page and the Help
/// screen both draw their text with this widget from the same
/// `AppStrings.guideSections`, so they cannot differ (ADR-032).
///
/// [detailed] adds the longer text of each section (Help); without it only the
/// short lines show (the last page of the wizard). [extraFor] lets a screen add
/// a button under a section (Help: the e-mail settings).
class GuideSectionsView extends StatelessWidget {
  const GuideSectionsView({
    super.key,
    required this.sections,
    this.detailed = false,
    this.extraFor,
  });

  final List<GuideSection> sections;
  final bool detailed;
  final Widget? Function(GuideSection section)? extraFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: GuideKeys.view,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections)
          Padding(
            key: GuideKeys.section(section.id),
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(section.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                for (final line in section.lines) _Bullet(text: line),
                if (detailed)
                  for (final line in section.details)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(line, style: theme.textTheme.bodyMedium),
                    ),
                ?extraFor?.call(section),
              ],
            ),
          ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
