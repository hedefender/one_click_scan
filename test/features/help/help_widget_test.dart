import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/first_run/first_run_keys.dart';
import 'package:one_click_scan/features/help/help_keys.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';
import 'package:one_click_scan/presentation/guide/guide_view.dart';
import 'package:one_click_scan/presentation/l10n/app_strings_el.dart';
import 'package:one_click_scan/presentation/l10n/app_strings_en.dart';
import 'package:one_click_scan/presentation/l10n/guide_section.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';

/// Phase 6.3 (ADR-032): the Help screen of Settings, "See the guide again",
/// and that the wizard page and Help read the same text.
void main() {
  Future<GetIt> pumpHome(WidgetTester tester, {String language = 'en'}) async {
    tester.view.physicalSize = const Size(800, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final values = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      config: AppConfig.forDeviceLanguage(language),
      store: values,
    );
    final seed = await build();
    // An install whose wizard was finished long ago.
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
      ),
    );
    final container = await build();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> openHelp(WidgetTester tester) async {
    await tester.tap(find.byKey(HomeKeys.settings));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(SettingsKeys.helpEntry),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(SettingsKeys.helpEntry));
    await tester.pumpAndSettle();
  }

  group('Help in Settings', () {
    testWidgets('the entry is in Settings and opens the Help screen', (
      tester,
    ) async {
      await pumpHome(tester);
      await openHelp(tester);

      expect(find.byKey(HelpKeys.page), findsOneWidget);
      expect(find.text('Help'), findsWidgets);
    });

    testWidgets('every section is there, with its title', (tester) async {
      await pumpHome(tester);
      await openHelp(tester);

      for (final section in const AppStringsEn().guideSections) {
        await tester.scrollUntilVisible(
          find.byKey(GuideKeys.section(section.id)),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.byKey(GuideKeys.section(section.id)),
          findsOneWidget,
          reason: section.id.name,
        );
        expect(find.text(section.title), findsOneWidget);
      }
    });

    testWidgets('"What the app does not cover" is in Help, neutral and plain', (
      tester,
    ) async {
      await pumpHome(tester);
      await openHelp(tester);
      final notCovered = find.byKey(
        GuideKeys.section(GuideSectionId.notCovered),
      );
      await tester.scrollUntilVisible(
        notCovered,
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('What the app does not cover'), findsOneWidget);
      expect(find.textContaining('does not fix bad shots'), findsOneWidget);
      expect(find.textContaining('Check the PDF and the text'), findsOneWidget);
    });

    testWidgets(
      'Help shows the details of a section, the wizard page does not',
      (tester) async {
        await pumpHome(tester);
        await openHelp(tester);

        await tester.scrollUntilVisible(
          find.text('The flash button only shows if the phone has a flash.'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text('The flash button only shows if the phone has a flash.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the Greek Help has the Greek titles', (tester) async {
      await pumpHome(tester, language: 'el');
      await tester.tap(find.byKey(HomeKeys.settings));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(SettingsKeys.helpEntry),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(SettingsKeys.helpEntry));
      await tester.pumpAndSettle();

      expect(find.text('Βοήθεια'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Τι δεν καλύπτει η εφαρμογή'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Τι δεν καλύπτει η εφαρμογή'), findsOneWidget);
    });

    testWidgets('the e-mail section sends the user to the e-mail settings', (
      tester,
    ) async {
      await pumpHome(tester);
      await openHelp(tester);
      await tester.scrollUntilVisible(
        find.byKey(HelpKeys.openMailSettings),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.byKey(HelpKeys.openMailSettings));
      await tester.pumpAndSettle();

      expect(find.byKey(HelpKeys.page), findsNothing);
      expect(find.byKey(SettingsKeys.save), findsOneWidget);
    });
  });

  group('See the guide again', () {
    testWidgets('shows the guide page and asks for no setting', (tester) async {
      final container = await pumpHome(tester);
      final before = await container<SettingsRepository>().load();
      await openHelp(tester);

      await tester.tap(find.byKey(HelpKeys.seeGuideAgain));
      await tester.pumpAndSettle();

      expect(find.byKey(HelpKeys.guidePage), findsOneWidget);
      expect(find.text('Before you start'), findsWidgets);
      expect(
        find.text('You can always find the above in Settings, under Help.'),
        findsOneWidget,
      );
      // No question of the wizard: no folder, no provider, no Next button.
      expect(find.byKey(FirstRunKeys.pickFolder), findsNothing);
      expect(find.byKey(FirstRunKeys.sender), findsNothing);
      expect(find.byKey(FirstRunKeys.next), findsNothing);
      // The settings are as they were.
      expect(await container<SettingsRepository>().load(), before);
    });

    testWidgets('has no "What the app does not cover" and no e-mail steps', (
      tester,
    ) async {
      await pumpHome(tester);
      await openHelp(tester);
      await tester.tap(find.byKey(HelpKeys.seeGuideAgain));
      await tester.pumpAndSettle();

      expect(find.text('What the app does not cover'), findsNothing);
      expect(find.text('Email and app password'), findsNothing);
      expect(find.text('Privacy'), findsOneWidget);
    });

    testWidgets('closing goes back to Help; the wizard does not start again', (
      tester,
    ) async {
      await pumpHome(tester);
      await openHelp(tester);
      await tester.tap(find.byKey(HelpKeys.seeGuideAgain));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HelpKeys.guideClose));
      await tester.pumpAndSettle();
      expect(find.byKey(HelpKeys.page), findsOneWidget);
      expect(find.byKey(FirstRunKeys.next), findsNothing);
    });
  });

  group('one text for the wizard page and Help', () {
    test('Greek and English have the same sections in the same order', () {
      final el = const AppStringsEl().guideSections;
      final en = const AppStringsEn().guideSections;
      expect([for (final s in el) s.id], [for (final s in en) s.id]);
      expect(
        [for (final s in el) s.inWizard],
        [for (final s in en) s.inWizard],
      );
      for (var i = 0; i < el.length; i++) {
        expect(el[i].lines.length, en[i].lines.length, reason: el[i].id.name);
        expect(
          el[i].details.length,
          en[i].details.length,
          reason: el[i].id.name,
        );
      }
    });

    test('every section has a title and non-empty lines', () {
      for (final strings in [const AppStringsEl(), const AppStringsEn()]) {
        for (final section in strings.guideSections) {
          expect(section.title.trim(), isNotEmpty, reason: section.id.name);
          expect(section.lines, isNotEmpty, reason: section.id.name);
          for (final line in [...section.lines, ...section.details]) {
            expect(line.trim(), isNotEmpty, reason: section.id.name);
          }
        }
      }
    });

    test(
      '"what the app does not cover" and the e-mail steps are Help only',
      () {
        for (final strings in [const AppStringsEl(), const AppStringsEn()]) {
          final wizard = [
            for (final s in strings.guideSections)
              if (s.inWizard) s.id,
          ];
          expect(wizard, isNot(contains(GuideSectionId.notCovered)));
          expect(wizard, isNot(contains(GuideSectionId.email)));
          expect(
            wizard,
            containsAll([
              GuideSectionId.mode,
              GuideSectionId.flash,
              GuideSectionId.lowLight,
              GuideSectionId.tips,
              GuideSectionId.multi,
              GuideSectionId.cancel,
              GuideSectionId.privacy,
            ]),
          );
        }
      },
    );

    test('the numbers in the texts are the ones of the app', () {
      final text = [
        for (final s in const AppStringsEn().guideSections) ...s.lines,
      ].join(' ');
      expect(text, contains('up to 25 pages'));
      expect(text, contains('after 2 minutes'));
      expect(text, contains('about 18 MB for Gmail'));
      expect(text, contains('about 14 MB for Outlook and Yahoo'));
    });

    test('the last line is the one that was asked for', () {
      expect(
        const AppStringsEl().guideLastLine,
        'Τα παραπάνω τα βρίσκεις πάντα στις Ρυθμίσεις, στη Βοήθεια.',
      );
      expect(
        const AppStringsEn().guideLastLine,
        'You can always find the above in Settings, under Help.',
      );
    });
  });
}
