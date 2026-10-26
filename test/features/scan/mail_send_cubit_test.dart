import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/destination_mode.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/mail_send_mode.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/ports/draft_sharer.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/scan/mail_send_cubit.dart';
import 'package:one_click_scan/features/scan/mail_send_state.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';

void main() {
  late MailTestRig mail;
  late SettingsRepository repository;
  late MailSendCubit cubit;
  late CapturingLogger logger;

  const pdf = StoredPdf(
    fileName: '2026-10-21_19-05-12.pdf',
    uri: 'content://com.example.test/document/pdf%2F2026-10-21_19-05-12.pdf',
    pageCount: 1,
    textPageCount: 1,
    byteSize: 150000,
  );

  setUp(() async {
    mail = MailTestRig()..storePassword();
    logger = CapturingLogger();
    final container = await buildTestContainer(
      mail: mail.services,
      logger: logger,
    );
    repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
      ),
    );
    cubit = container<MailSendCubit>();
  });

  tearDown(() => cubit.close());

  test('nothing happens before the PDF is known', () async {
    await cubit.send();
    expect(mail.sender.sent, isEmpty);
    expect(cubit.state.phase, MailPhase.idle);
  });

  test('attach reads the mode of the settings', () async {
    await repository.save(
      (await repository.load()).copyWith(mailSendMode: MailSendMode.shareDraft),
    );
    await cubit.attach(pdf);

    expect(cubit.state.mode, MailSendMode.shareDraft);
  });

  test(
    'send: sending, then sent, with the message the use case builds',
    () async {
      await cubit.attach(pdf);
      final phases = <MailPhase>[];
      final sub = cubit.stream.listen((s) => phases.add(s.phase));

      await cubit.send();
      await pumpEventQueue();
      await sub.cancel();

      expect(phases, [MailPhase.sending, MailPhase.sent]);
      expect(cubit.state.outcome, isNull);
      expect(
        mail.sender.sent.single.subject,
        'One Click Scan - 2026-10-21_19-05-12',
      );
      expect(mail.sender.sent.single.to, [testAccount]);
    },
  );

  test(
    'a failure is a state with its outcome, and a new try can succeed',
    () async {
      await cubit.attach(pdf);
      mail.sender.outcome = const MailAuthFailed();

      await cubit.send();
      expect(cubit.state.phase, MailPhase.failed);
      expect(cubit.state.outcome, isA<MailAuthFailed>());
      expect(cubit.state.busy, isFalse);

      mail.sender.outcome = const MailSent();
      await cubit.send();
      expect(cubit.state.phase, MailPhase.sent);
      expect(cubit.state.outcome, isNull);
      expect(mail.sender.sent, hasLength(2));
    },
  );

  test('no automatic retry: one failure is one attempt', () async {
    await cubit.attach(pdf);
    mail.sender.outcome = const MailNetworkError();

    await cubit.send();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(mail.sender.sent, hasLength(1));
  });

  test(
    'settings that are not complete lead to the settings, with no attempt',
    () async {
      mail.credentials.stored = null;
      await cubit.attach(pdf);

      await cubit.send();

      expect(cubit.state.phase, MailPhase.failed);
      expect(cubit.state.needsSettings, isTrue);
      expect(mail.sender.sent, isEmpty);
    },
  );

  test(
    'settings are read at each tap: a password set meanwhile is used',
    () async {
      mail.credentials.stored = null;
      await cubit.attach(pdf);
      await cubit.send();
      expect(cubit.state.needsSettings, isTrue);

      mail.storePassword();
      await cubit.send();

      expect(cubit.state.phase, MailPhase.sent);
    },
  );

  test('a second tap while sending does nothing', () async {
    await cubit.attach(pdf);
    mail.sender.hold = Completer<MailOutcome>();

    final first = cubit.send();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(cubit.state.busy, isTrue);
    await cubit.send();
    mail.sender.hold!.complete(const MailSent());
    await first;

    expect(mail.sender.sent, hasLength(1));
    expect(cubit.state.phase, MailPhase.sent);
  });

  test('cancel ends a send in progress and goes back to idle', () async {
    await cubit.attach(pdf);
    mail.sender.hold = Completer<MailOutcome>();

    final sending = cubit.send();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    cubit.cancel();
    await sending;

    expect(cubit.state.phase, MailPhase.idle);
    expect(cubit.state.outcome, isNull);
    // Cancelled is not a failure and a new try is possible.
    mail.sender.hold = null;
    await cubit.send();
    expect(cubit.state.phase, MailPhase.sent);
  });

  test('the share mode opens the mail app instead of sending', () async {
    await repository.save(
      (await repository.load()).copyWith(mailSendMode: MailSendMode.shareDraft),
    );
    await cubit.attach(pdf);

    await cubit.send();

    expect(mail.sender.sent, isEmpty);
    expect(mail.sharer.shared, hasLength(1));
    expect(cubit.state.draft, DraftShareResult.opened);
    expect(cubit.state.phase, MailPhase.idle);
  });

  test('after a failed send "open in the mail app" shares the PDF', () async {
    await repository.save(
      (await repository.load()).copyWith(
        destinationMode: DestinationMode.custom,
        customDestination: testDestination,
      ),
    );
    await cubit.attach(pdf);
    mail.sender.outcome = const MailNetworkError();
    await cubit.send();

    await cubit.openMailApp();

    final shared = mail.sharer.shared.single;
    expect(shared['to'], [testDestination]);
    expect(shared['uri'], pdf.uri);
    expect(cubit.state.phase, MailPhase.failed, reason: 'the failure stays');
    expect(cubit.state.draft, DraftShareResult.opened);
  });

  test('the answers of the mail app are kept: no app, or failed', () async {
    await cubit.attach(pdf);
    mail.sharer.result = DraftShareResult.noApp;
    await cubit.openMailApp();
    expect(cubit.state.draft, DraftShareResult.noApp);

    mail.sharer.result = DraftShareResult.failed;
    await cubit.openMailApp();
    expect(cubit.state.draft, DraftShareResult.failed);
  });

  test(
    'a sender that throws is a state, and nothing secret is logged',
    () async {
      await cubit.attach(pdf);
      mail.sender.throwOnSend = StateError('boom $canarySecret $testAccount');

      await cubit.send();

      expect(cubit.state.phase, MailPhase.failed);
      expect(cubit.state.outcome, isA<MailUnknown>());
      expect(logger.all, isNot(contains(canarySecret)));
      expect(logger.all, isNot(contains(testAccount)));
    },
  );

  test('closing the cubit cancels a send that is still running', () async {
    await cubit.attach(pdf);
    mail.sender.hold = Completer<MailOutcome>();
    final sending = cubit.send();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await cubit.close();
    await sending;

    expect(cubit.isClosed, isTrue);
  });
}
