import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
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
  test('every provider has instructions in both languages, in steps; Outlook '
      'has none (no app password for SMTP)', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    for (final provider in MailProviderId.values) {
      final steps = provider == MailProviderId.outlook ? 0 : 4;
      expect(
        el.mailHelpSteps(provider),
        hasLength(steps),
        reason: provider.name,
      );
      expect(
        en.mailHelpSteps(provider),
        hasLength(steps),
        reason: provider.name,
      );
    }
    expect(el.mailHelpNote(MailProviderId.gmail), isNotNull);
    expect(en.mailHelpNote(MailProviderId.gmail), contains('administrator'));
    expect(en.mailHelpNote(MailProviderId.outlook), isNull);
    expect(en.mailGuideOutlook, contains('OAuth'));
    expect(el.mailGuideOutlook, contains('OAuth'));
  });

  test('the steps do not invent menu names of Google that could not be read; '
      'the page is opened by the button', () async {
    final en = await AppStrings.delegate.load(const Locale('en'));
    final steps = en.mailHelpSteps(MailProviderId.gmail).join(' ');

    expect(steps, contains('Open the provider page'));
    expect(steps, isNot(contains('Security >')));
    expect(steps, isNot(contains('Manage your Google Account')));
  });

  test('the guide says it is not the normal password, shown once, no spaces, '
      'in both languages', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(en.mailGuideWhat, contains('not the normal password'));
    expect(el.mailGuideWhat, contains('Δεν είναι ο κανονικός κωδικός'));
    expect(
      en.mailGuideReminder,
      allOf(contains('only once'), contains('spaces')),
    );
    expect(
      el.mailGuideReminder,
      allOf(contains('μία μόνο φορά'), contains('κενά')),
    );
  });

  test('the refused-sign-in text names MFA, the app password and the '
      'administrator, in both languages', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(
      en.mailFailedAuth,
      allOf(
        contains('MFA'),
        contains('app password'),
        contains('administrator'),
      ),
    );
    expect(
      el.mailFailedAuth,
      allOf(
        contains('MFA'),
        contains('κωδικός εφαρμογής'),
        contains('διαχειριστής'),
      ),
    );
  });

  test('the share texts say the e-mail app uses the account it already '
      'has, in both languages', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(
      en.mailShareNote,
      contains('account that the e-mail app already has'),
    );
    expect(
      el.mailShareNote,
      contains('λογαριασμός που έχει ήδη επιλεγμένο η εφαρμογή email'),
    );
  });

  test('the diagnostic line holds the step and the code only', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(
      en.mailDiagnostic(MailStage.authentication, 535),
      'Step: authentication, code 535',
    );
    expect(
      el.mailDiagnostic(MailStage.authentication, 535),
      'Στάδιο: ταυτοποίηση, κωδικός 535',
    );
    expect(en.mailDiagnostic(MailStage.connection, null), 'Step: connection');
    expect(en.mailDiagnostic(MailStage.tls, null), 'Step: TLS');
    expect(
      el.mailDiagnostic(MailStage.sending, 550),
      'Στάδιο: αποστολή, κωδικός 550',
    );
  });

  test('the Outlook text says it waits for OAuth and points to the backup '
      'way, in both languages', () async {
    final el = await AppStrings.delegate.load(const Locale('el'));
    final en = await AppStrings.delegate.load(const Locale('en'));

    expect(en.mailOutlookWarning, allOf(contains('OAuth'), contains('backup')));
    expect(
      el.mailOutlookWarning,
      allOf(contains('OAuth'), contains('εφεδρική')),
    );
  });

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
