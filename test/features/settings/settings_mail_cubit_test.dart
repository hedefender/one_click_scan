import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/mail_send_mode.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/settings/settings_editor_cubit.dart';
import 'package:one_click_scan/features/settings/settings_editor_state.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';

void main() {
  late MailTestRig mail;
  late InMemoryKeyValueStore keyValues;
  late CapturingLogger logger;
  late SettingsRepository repository;
  late SettingsEditorCubit cubit;

  Future<void> start({bool stored = false}) async {
    mail = MailTestRig();
    if (stored) mail.storePassword();
    keyValues = InMemoryKeyValueStore();
    logger = CapturingLogger();
    final container = await buildTestContainer(
      store: keyValues,
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
    cubit = container<SettingsEditorCubit>();
    await cubit.start();
  }

  tearDown(() => cubit.close());

  group('the stored password', () {
    test(
      'start tells whether one is stored for this provider and account',
      () async {
        await start(stored: true);
        expect(cubit.state.hasStoredPassword, isTrue);
        await cubit.close();

        await start();
        expect(cubit.state.hasStoredPassword, isFalse);
      },
    );

    test(
      'a password of another account is not "stored" for this one',
      () async {
        await start();
        mail.storePassword(account: 'someone.else@example.test');
        await cubit.close();
        final container = await buildTestContainer(
          store: keyValues,
          mail: mail.services,
        );
        cubit = container<SettingsEditorCubit>();
        await cubit.start();

        expect(cubit.state.hasStoredPassword, isFalse);
      },
    );

    test('typing a password is a change that can be saved, and prints as '
        'nothing', () async {
      await start();
      cubit.setPassword(canarySecret);

      expect(cubit.state.hasChanges, isTrue);
      expect(cubit.state.canSave, isTrue);
      expect('${cubit.state}', isNot(contains(canarySecret)));
    });

    test('Save writes it to the secure store with the provider and the '
        'account, and clears the field', () async {
      await start();
      cubit.setSenderAccount(' $testAccount ');
      cubit.setPassword(canarySecret);

      await cubit.save();

      final stored = mail.credentials.stored!;
      expect(stored.provider, MailProviderId.gmail);
      expect(stored.accountEmail, testAccount);
      expect(stored.secret, canarySecret);
      expect(cubit.state.password, '');
      expect(cubit.state.hasStoredPassword, isTrue);
      expect(cubit.state.hasChanges, isFalse);
    });

    test(
      'the password never reaches the key/value store of the settings',
      () async {
        await start();
        cubit.setPassword(canarySecret);
        await cubit.save();

        expect(
          keyValues.data.values.map((v) => '$v').join('|'),
          isNot(contains(canarySecret)),
        );
        expect(keyValues.data.keys.any((k) => k.contains('password')), isFalse);
      },
    );

    test('Save without a typed password leaves the stored one alone', () async {
      await start(stored: true);
      cubit.setSenderAccount(testAccount.toUpperCase());

      await cubit.save();

      expect(mail.credentials.stored!.secret, canarySecret);
      // Same address, only the case changed: the password is still its own.
      expect(cubit.state.hasStoredPassword, isTrue);
    });

    test('changing the account without a new password: none is stored for the '
        'new one', () async {
      await start(stored: true);
      cubit.setSenderAccount('another@example.test');

      await cubit.save();

      expect(cubit.state.hasStoredPassword, isFalse);
    });

    test('a failing secure store does not lose the other settings, and the '
        'secret is not logged', () async {
      await start();
      mail.credentials.failWrite = StateError('keystore $canarySecret');
      cubit.setSenderAccount('new@example.test');
      cubit.setPassword(canarySecret);

      await cubit.save();

      expect((await repository.load()).senderAccount, 'new@example.test');
      expect(cubit.state.hasStoredPassword, isFalse);
      expect(logger.all, isNot(contains(canarySecret)));
    });

    test('discard throws away the typed password', () async {
      await start();
      cubit.setPassword(canarySecret);
      cubit.discardChanges();

      expect(cubit.state.password, '');
      expect(cubit.state.hasChanges, isFalse);
    });

    test('delete removes the stored password and says so', () async {
      await start(stored: true);

      await cubit.deletePassword();

      expect(mail.credentials.stored, isNull);
      expect(cubit.state.hasStoredPassword, isFalse);
      expect(cubit.state.passwordNotice, MailPasswordNotice.deleted);
    });

    test('a delete that fails says so and keeps the state', () async {
      await start(stored: true);
      mail.credentials.failDelete = StateError('x');

      await cubit.deletePassword();

      expect(cubit.state.hasStoredPassword, isTrue);
      expect(cubit.state.passwordNotice, MailPasswordNotice.deleteFailed);
    });

    test('the password can be shown and hidden', () async {
      await start();
      expect(cubit.state.passwordVisible, isFalse);
      cubit.togglePasswordVisible();
      expect(cubit.state.passwordVisible, isTrue);
      cubit.togglePasswordVisible();
      expect(cubit.state.passwordVisible, isFalse);
    });
  });

  group('the connection test', () {
    test('without any password it asks for one and does not connect', () async {
      await start();

      await cubit.testConnection();

      expect(cubit.state.mailTest, MailTestStatus.needsPassword);
      expect(mail.sender.checks, 0);
    });

    test('signs in with what is on the screen, and sends nothing', () async {
      await start();
      cubit.selectProvider(MailProviderId.yahoo);
      cubit.setSenderAccount('typed@example.test');
      cubit.setPassword(canarySecret);

      await cubit.testConnection();

      expect(cubit.state.mailTest, MailTestStatus.ok);
      expect(mail.sender.checks, 1);
      expect(mail.sender.sent, isEmpty);
      expect(mail.sender.providers.single.id, 'yahoo');
      expect(mail.sender.auths.single.accountEmail, 'typed@example.test');
      expect(mail.sender.auths.single.secret, canarySecret);
    });

    test('with an empty field it uses the stored password', () async {
      await start(stored: true);

      await cubit.testConnection();

      expect(cubit.state.mailTest, MailTestStatus.ok);
      expect(mail.sender.auths.single.secret, canarySecret);
    });

    test('the stored password of another account is not used', () async {
      await start(stored: true);
      cubit.setSenderAccount('another@example.test');

      await cubit.testConnection();

      expect(cubit.state.mailTest, MailTestStatus.needsPassword);
      expect(mail.sender.checks, 0);
    });

    final cases = <MailOutcome, MailTestStatus>{
      const MailAuthFailed(): MailTestStatus.authFailed,
      const MailNetworkError(): MailTestStatus.network,
      const MailRejected(421): MailTestStatus.rejected,
      const MailUnknown(): MailTestStatus.unknown,
    };
    for (final entry in cases.entries) {
      test('${entry.key.runtimeType} is ${entry.value.name}', () async {
        await start();
        mail.sender.outcome = entry.key;
        cubit.setPassword(canarySecret);

        await cubit.testConnection();

        expect(cubit.state.mailTest, entry.value);
      });
    }

    test('the reply code of a rejection is kept for the message', () async {
      await start();
      mail.sender.outcome = const MailRejected(421);
      cubit.setPassword(canarySecret);
      await cubit.testConnection();
      expect(cubit.state.mailTestCode, 421);
    });

    test('editing the account, the provider or the password resets the '
        'result', () async {
      await start();
      cubit.setPassword(canarySecret);
      await cubit.testConnection();
      expect(cubit.state.mailTest, MailTestStatus.ok);

      cubit.setPassword('${canarySecret}x');
      expect(cubit.state.mailTest, MailTestStatus.idle);
      await cubit.testConnection();
      cubit.setSenderAccount('b@example.test');
      expect(cubit.state.mailTest, MailTestStatus.idle);
      await cubit.testConnection();
      cubit.selectProvider(MailProviderId.outlook);
      expect(cubit.state.mailTest, MailTestStatus.idle);
    });

    test('a second tap while it runs is ignored', () async {
      await start();
      cubit.setPassword(canarySecret);
      mail.sender.holdCheck = Completer<void>();

      final first = cubit.testConnection();
      await pumpEventQueue();
      expect(cubit.state.mailTest, MailTestStatus.running);
      await cubit.testConnection();
      mail.sender.holdCheck!.complete();
      await first;

      expect(mail.sender.checks, 1);
      expect(cubit.state.mailTest, MailTestStatus.ok);
    });

    test('a sender that throws is an unknown result, and nothing secret is '
        'logged', () async {
      await start();
      cubit.setPassword(canarySecret);
      mail.sender.throwOnCheck = StateError('boom $canarySecret $testAccount');

      await cubit.testConnection();

      expect(cubit.state.mailTest, MailTestStatus.unknown);
      expect(logger.all, isNot(contains(canarySecret)));
      expect(logger.all, isNot(contains(testAccount)));
    });
  });

  group('the way to send', () {
    test('is saved at once', () async {
      await start();
      expect(cubit.state.saved!.mailSendMode, MailSendMode.sendNow);

      await cubit.selectSendMode(MailSendMode.shareDraft);

      expect(cubit.state.saved!.mailSendMode, MailSendMode.shareDraft);
      expect((await repository.load()).mailSendMode, MailSendMode.shareDraft);
      // It is not part of the unsaved draft.
      expect(cubit.state.hasChanges, isFalse);
    });
  });
}
