import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/features/first_run/first_run_keys.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/presentation/guide/guide_view.dart';
import 'package:one_click_scan/presentation/l10n/app_strings_en.dart';
import 'package:one_click_scan/presentation/l10n/guide_section.dart';

import '../../support/fakes.dart';

/// Phase 6.3 (ADR-032): the explanations of the wizard steps and the last page
/// (the guide), which asks nothing.
void main() {
  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.byKey(FirstRunKeys.next));
    await tester.pumpAndSettle();
  }

  Future<void> pumpWizard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await buildTestContainer();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
  }

  Future<void> toGuide(WidgetTester tester) async {
    await pumpWizard(tester);
    await tapNext(tester); // welcome
    await tester.tap(find.byKey(FirstRunKeys.pickFolder));
    await tester.pumpAndSettle();
    await tapNext(tester); // folder
    await tester.tap(find.text('Gmail'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FirstRunKeys.sender),
      'sender@example.com',
    );
    await tester.pumpAndSettle();
    await tapNext(tester); // mail
    await tapNext(tester); // gallery
    await tester.tap(find.byKey(FirstRunKeys.flowPreview));
    await tester.pumpAndSettle();
    await tapNext(tester); // flow
  }

  group('the choice steps explain themselves', () {
    testWidgets('folder, e-mail and Gallery say that it can be changed later', (
      tester,
    ) async {
      await pumpWizard(tester);
      const note = 'You can change this later in Settings.';

      await tapNext(tester); // welcome -> folder
      expect(find.textContaining(note), findsOneWidget);

      await tester.tap(find.byKey(FirstRunKeys.pickFolder));
      await tester.pumpAndSettle();
      await tapNext(tester); // folder -> mail
      expect(find.textContaining(note), findsOneWidget);
      expect(
        find.textContaining('Provider: the email account'),
        findsOneWidget,
      );

      await tester.tap(find.text('Gmail'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(FirstRunKeys.sender),
        'sender@example.com',
      );
      await tester.pumpAndSettle();
      await tapNext(tester); // mail -> gallery
      expect(find.textContaining(note), findsOneWidget);

      await tapNext(tester); // gallery -> flow
      expect(
        find.textContaining('You can change this later in Settings.'),
        findsOneWidget,
        reason: 'the flow step already said it',
      );
    });
  });

  group('the last page of the wizard', () {
    testWidgets('comes after the last setting and has the guide', (
      tester,
    ) async {
      await toGuide(tester);

      expect(find.text('Step 6 of 6'), findsOneWidget);
      expect(find.byKey(GuideKeys.view), findsOneWidget);
      for (final section in const AppStringsEn().guideSections) {
        final shown = section.inWizard;
        expect(
          find.byKey(GuideKeys.section(section.id)),
          shown ? findsOneWidget : findsNothing,
          reason: section.id.name,
        );
      }
    });

    testWidgets('has the lines asked for', (tester) async {
      await toGuide(tester);

      expect(find.textContaining('Single page:'), findsOneWidget);
      expect(find.textContaining('Multiple pages:'), findsOneWidget);
      expect(find.text('Flash and light'), findsOneWidget);
      expect(find.textContaining('Torch (On)'), findsOneWidget);
      expect(find.textContaining('goes back to "Auto"'), findsOneWidget);
      expect(find.text('Low light'), findsOneWidget);
      expect(find.text('Tips for a good shot'), findsOneWidget);
      expect(find.textContaining('shadow'), findsOneWidget);
      expect(find.textContaining('reflections'), findsOneWidget);
      expect(find.textContaining('stands out from the paper'), findsOneWidget);
      expect(find.textContaining('Hold the phone steady'), findsOneWidget);
      expect(find.text('Cancel and Discard'), findsOneWidget);
      expect(find.textContaining('up to 25 pages'), findsOneWidget);
      expect(find.textContaining('Google Photos'), findsOneWidget);
    });

    testWidgets('the last line points to Help and is the last thing on it', (
      tester,
    ) async {
      await toGuide(tester);

      final last = find.byKey(GuideKeys.lastLine);
      expect(last, findsOneWidget);
      expect(
        tester.widget<Text>(last).data,
        'You can always find the above in Settings, under Help.',
      );
      final sections = find.byKey(GuideKeys.section(GuideSectionId.privacy));
      expect(
        tester.getTopLeft(last).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(sections).dy),
      );
    });

    testWidgets('does not have "What the app does not cover"', (tester) async {
      await toGuide(tester);

      expect(find.text('What the app does not cover'), findsNothing);
      expect(find.textContaining('does not fix bad shots'), findsNothing);
    });

    testWidgets('Finish ends the wizard and opens home', (tester) async {
      await toGuide(tester);
      expect(find.text('Finish'), findsOneWidget);

      await tapNext(tester);

      expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    });

    testWidgets('Back goes to the last setting', (tester) async {
      await toGuide(tester);

      await tester.tap(find.byKey(FirstRunKeys.back));
      await tester.pumpAndSettle();

      expect(find.text('Step 5 of 6'), findsOneWidget);
      expect(find.byKey(FirstRunKeys.flowPreview), findsOneWidget);
    });
  });
}
