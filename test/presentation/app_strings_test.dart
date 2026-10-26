import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/presentation/l10n/app_strings.dart';

void main() {
  mailStringsTests();

  test('delegate supports Greek and English only', () {
    expect(AppStrings.delegate.isSupported(const Locale('el')), isTrue);
    expect(AppStrings.delegate.isSupported(const Locale('en')), isTrue);
    expect(AppStrings.delegate.isSupported(const Locale('fr')), isFalse);
  });

  test('loads the right language', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(el.actionNext, 'Επόμενο');
    expect(en.actionNext, 'Next');
  });

  test('parameterised strings interpolate in both languages', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(en.wizardStepIndicator(2, 4), 'Step 2 of 4');
    expect(el.wizardStepIndicator(2, 4), 'Βήμα 2 από 4');
    expect(en.folderSelected('Scans'), contains('Scans'));
    expect(el.folderSelected('Scans'), contains('Scans'));
  });

  test('the Gallery note explains what sharing to the Gallery means', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(en.galleryNote, contains('Gallery'));
    expect(el.galleryNote, contains('Gallery'));
    expect(en.galleryNote.length, greaterThan(80));
    expect(el.galleryNote.length, greaterThan(80));
  });
}

// Phase 4: the words of the mail screens.
void mailStringsTests() {
  test('every provider has instructions in both languages, in steps', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    for (final provider in MailProviderId.values) {
      expect(el.mailHelpSteps(provider), hasLength(4), reason: provider.name);
      expect(en.mailHelpSteps(provider), hasLength(4), reason: provider.name);
      expect(el.mailHelpNote(provider), isNotNull);
      expect(en.mailHelpNote(provider), isNotNull);
    }
  });

  test(
    'the steps do not invent menu names of Google that could not be read',
    () async {
      final en = await AppStrings.delegate.load(const Locale('en'));
      final steps = en.mailHelpSteps(MailProviderId.gmail).join(' ');

      // The page of the app passwords is named by its address only.
      expect(steps, contains('myaccount.google.com/apppasswords'));
      expect(steps, isNot(contains('Security > ')));
    },
  );

  test(
    'the Outlook warning says it is not confirmed, in both languages',
    () async {
      final el = await AppStrings.delegate.load(const Locale('el'));
      final en = await AppStrings.delegate.load(const Locale('en'));

      expect(en.mailOutlookWarning, contains('not confirmed'));
      expect(el.mailOutlookWarning, contains('επιβεβαιωμένο'));
    },
  );

  test('no text promises delivery', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(en.mailSent, 'The message was sent from the e-mail server.');
    expect(el.mailSent, 'Το μήνυμα στάλθηκε από τον διακομιστή email.');
    for (final text in [en.mailSent, el.mailSent, en.mailDraftOpened]) {
      expect(text.toLowerCase(), isNot(contains('deliver')));
      expect(text, isNot(contains('παραδόθηκε')));
    }
  });

  test(
    'failure texts carry no placeholder of a secret, and the code shows',
    () async {
      final en = await AppStrings.delegate.load(const Locale('en'));

      expect(en.mailFailedRejected(550), contains('550'));
      expect(en.mailFailedRejected(0), isNot(contains('code')));
    },
  );
}
