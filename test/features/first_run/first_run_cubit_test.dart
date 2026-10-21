import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/destination_mode.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/usecases/load_settings.dart';
import 'package:one_click_scan/features/first_run/first_run_cubit.dart';
import 'package:one_click_scan/features/first_run/first_run_state.dart';

import '../../support/fakes.dart';

void main() {
  late InMemoryKeyValueStore store;
  late FakeStorageFolderPicker picker;
  late RecordingLogger logger;
  late SettingsRepository repository;
  late FirstRunCubit cubit;

  setUp(() async {
    store = InMemoryKeyValueStore();
    picker = FakeStorageFolderPicker();
    logger = RecordingLogger();
    final container = await buildTestContainer(
      store: store,
      picker: picker,
      logger: logger,
    );
    repository = container<SettingsRepository>();
    cubit = container<FirstRunCubit>();
    await cubit.start();
  });

  tearDown(() => cubit.close());

  Future<void> completeFolderStep() async {
    await cubit.next(); // welcome -> folder
    await cubit.pickFolder();
    await cubit.next(); // folder -> mail
  }

  Future<void> completeMailStep() async {
    cubit.selectProvider(MailProviderId.gmail);
    cubit.setSenderAccount('sender@example.com');
    await cubit.next(); // mail -> gallery
  }

  test('starts on the welcome step with the default language', () {
    expect(cubit.state.step, FirstRunStep.welcome);
    expect(cubit.state.language, AppLanguage.en);
    expect(cubit.state.completed, isFalse);
  });

  test('selecting a language persists it immediately', () async {
    await cubit.selectLanguage(AppLanguage.el);

    expect(cubit.state.language, AppLanguage.el);
    expect((await LoadSettings(repository)()).language, AppLanguage.el);
  });

  test(
    'welcome step can always be left; back on the first step is a no-op',
    () async {
      cubit.back();
      expect(cubit.state.step, FirstRunStep.welcome);

      await cubit.next();
      expect(cubit.state.step, FirstRunStep.folder);
    },
  );

  group('folder step', () {
    test('cannot continue without a folder and shows the error', () async {
      await cubit.next();
      await cubit.next();

      expect(cubit.state.step, FirstRunStep.folder);
      expect(cubit.state.showErrors, isTrue);
      expect(
        cubit.state.errorsFor(FirstRunStep.folder),
        contains(FirstRunError.folderMissing),
      );
    });

    test('a picked folder is stored and persisted on next', () async {
      await cubit.next();
      await cubit.pickFolder();

      expect(cubit.state.folder, testFolder);
      expect(cubit.state.folderStatus, FolderPickStatus.idle);

      await cubit.next();
      expect(cubit.state.step, FirstRunStep.mail);
      expect((await LoadSettings(repository)()).storageFolder, testFolder);
    });

    test('cancelling the picker keeps the previous state', () async {
      picker.result = null;
      await cubit.next();
      await cubit.pickFolder();

      expect(cubit.state.folder, isNull);
      expect(cubit.state.folderStatus, FolderPickStatus.idle);
      expect(picker.pickCalls, 1);
    });

    test(
      'a platform failure is reported and logged without user content',
      () async {
        picker.error = const StorageFolderException('boom');
        await cubit.next();
        await cubit.pickFolder();

        expect(cubit.state.folderStatus, FolderPickStatus.failed);
        expect(logger.messages, isNotEmpty);
        expect(logger.messages.join(), isNot(contains('content://')));
      },
    );
  });

  group('mail step', () {
    test('requires provider and a valid sender account', () async {
      await completeFolderStep();
      await cubit.next();

      expect(cubit.state.step, FirstRunStep.mail);
      expect(
        cubit.state.errorsFor(FirstRunStep.mail),
        containsAll(<FirstRunError>[
          FirstRunError.providerMissing,
          FirstRunError.senderInvalid,
        ]),
      );

      cubit.setSenderAccount('not-an-email');
      expect(
        cubit.state.errorsFor(FirstRunStep.mail),
        contains(FirstRunError.senderInvalid),
      );
    });

    test('own destination does not need a custom address', () async {
      await completeFolderStep();
      cubit.selectProvider(MailProviderId.yahoo);
      cubit.setSenderAccount('sender@example.com');

      expect(cubit.state.errorsFor(FirstRunStep.mail), isEmpty);
    });

    test('custom destination must be a valid address', () async {
      await completeFolderStep();
      cubit.selectProvider(MailProviderId.outlook);
      cubit.setSenderAccount('sender@example.com');
      cubit.selectDestinationMode(DestinationMode.custom);

      expect(cubit.state.errorsFor(FirstRunStep.mail), {
        FirstRunError.customDestinationInvalid,
      });

      cubit.setCustomDestination('other@example.com');
      expect(cubit.state.errorsFor(FirstRunStep.mail), isEmpty);
    });

    test('values are trimmed when persisted', () async {
      await completeFolderStep();
      cubit.selectProvider(MailProviderId.gmail);
      cubit.setSenderAccount('  sender@example.com  ');
      cubit.selectDestinationMode(DestinationMode.custom);
      cubit.setCustomDestination(' other@example.com ');
      await cubit.next();

      final saved = await LoadSettings(repository)();
      expect(saved.senderAccount, 'sender@example.com');
      expect(saved.customDestination, 'other@example.com');
      expect(saved.effectiveDestination, 'other@example.com');
    });

    test(
      'switching back to own destination drops the custom address',
      () async {
        await completeFolderStep();
        cubit.selectProvider(MailProviderId.gmail);
        cubit.setSenderAccount('sender@example.com');
        cubit.setCustomDestination('other@example.com');
        await cubit.next();

        final saved = await LoadSettings(repository)();
        expect(saved.destinationMode, DestinationMode.own);
        expect(saved.customDestination, isNull);
      },
    );
  });

  group('gallery step and completion', () {
    test(
      'finishing persists everything and marks first run completed',
      () async {
        await completeFolderStep();
        await completeMailStep();
        expect(cubit.state.step, FirstRunStep.gallery);

        cubit.setSaveToGallery(true);
        await cubit.next();

        expect(cubit.state.completed, isTrue);
        final saved = await LoadSettings(repository)();
        expect(saved.firstRunCompleted, isTrue);
        expect(saved.saveToGallery, isTrue);
        expect(saved.storageFolder, testFolder);
        expect(saved.mailProvider, MailProviderId.gmail);
      },
    );

    test('Gallery copies are off unless the user turns them on', () async {
      await completeFolderStep();
      await completeMailStep();
      await cubit.next();

      expect((await LoadSettings(repository)()).saveToGallery, isFalse);
    });

    test('going back clears validation errors', () async {
      await cubit.next();
      await cubit.next(); // folder error
      expect(cubit.state.showErrors, isTrue);

      cubit.back();
      expect(cubit.state.step, FirstRunStep.welcome);
      expect(cubit.state.showErrors, isFalse);
    });

    test('an interrupted wizard preloads earlier answers on start', () async {
      await cubit.next();
      await cubit.pickFolder();
      await cubit.next();
      await cubit.selectLanguage(AppLanguage.el);

      // Same store, new container and cubit (app killed and reopened).
      final container = await buildTestContainer(store: store);
      final fresh = container<FirstRunCubit>();
      await fresh.start();

      expect(fresh.state.folder, testFolder);
      expect(fresh.state.language, AppLanguage.el);
      expect(fresh.state.step, FirstRunStep.welcome);
      await fresh.close();
    });
  });
}
