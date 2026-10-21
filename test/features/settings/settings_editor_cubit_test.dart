import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/destination_mode.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/storage_folder.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/validation/mail_settings_validation.dart';
import 'package:one_click_scan/features/settings/settings_editor_cubit.dart';
import 'package:one_click_scan/features/settings/settings_editor_state.dart';

import '../../support/fakes.dart';

void main() {
  late FakeStorageFolderPicker picker;
  late SettingsRepository repository;
  late SettingsEditorCubit cubit;

  setUp(() async {
    picker = FakeStorageFolderPicker();
    final container = await buildTestContainer(picker: picker);
    repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: 'sender@example.com',
      ),
    );
    cubit = container<SettingsEditorCubit>();
    await cubit.start();
  });

  tearDown(() => cubit.close());

  test('start loads the stored settings into the draft', () {
    final state = cubit.state;
    expect(state.isLoaded, isTrue);
    expect(state.provider, MailProviderId.gmail);
    expect(state.senderAccount, 'sender@example.com');
    expect(state.hasChanges, isFalse);
    expect(state.canSave, isFalse);
    expect(state.folderAccessLost, isFalse);
  });

  test('editing the draft marks changes without persisting', () async {
    cubit.setSenderAccount('other@example.com');

    expect(cubit.state.hasChanges, isTrue);
    expect(cubit.state.canSave, isTrue);
    expect((await repository.load()).senderAccount, 'sender@example.com');
  });

  test('typing the stored value back is not a change', () {
    cubit.setSenderAccount('other@example.com');
    cubit.setSenderAccount('  sender@example.com ');

    expect(cubit.state.hasChanges, isFalse);
  });

  test('switching recipient mode and back is not a change', () {
    cubit.selectDestinationMode(DestinationMode.custom);
    expect(cubit.state.hasChanges, isTrue);
    cubit.selectDestinationMode(DestinationMode.own);
    expect(cubit.state.hasChanges, isFalse);
  });

  test('invalid draft reports the shared errors and cannot be saved', () {
    cubit.setSenderAccount('nope');
    cubit.selectDestinationMode(DestinationMode.custom);

    expect(
      cubit.state.errors,
      containsAll(<MailSettingsError>[
        MailSettingsError.senderInvalid,
        MailSettingsError.customDestinationInvalid,
      ]),
    );
    expect(cubit.state.hasChanges, isTrue);
    expect(cubit.state.canSave, isFalse);
  });

  test('save persists a valid draft and clears the change flag', () async {
    cubit.selectProvider(MailProviderId.outlook);
    cubit.setSenderAccount(' new@example.com ');
    cubit.selectDestinationMode(DestinationMode.custom);
    cubit.setCustomDestination('to@example.com');
    await cubit.save();

    final stored = await repository.load();
    expect(stored.mailProvider, MailProviderId.outlook);
    expect(stored.senderAccount, 'new@example.com');
    expect(stored.destinationMode, DestinationMode.custom);
    expect(stored.customDestination, 'to@example.com');
    expect(cubit.state.hasChanges, isFalse);
    expect(cubit.state.justSaved, isTrue);
  });

  test('save clears the custom destination when mode is own', () async {
    cubit.selectDestinationMode(DestinationMode.custom);
    cubit.setCustomDestination('to@example.com');
    await cubit.save();
    cubit.selectDestinationMode(DestinationMode.own);
    await cubit.save();

    expect((await repository.load()).customDestination, isNull);
  });

  test('save does nothing when the draft is invalid', () async {
    cubit.setSenderAccount('nope');
    await cubit.save();

    expect((await repository.load()).senderAccount, 'sender@example.com');
    expect(cubit.state.justSaved, isFalse);
  });

  test('discardChanges restores the stored values', () {
    cubit.selectProvider(MailProviderId.yahoo);
    cubit.setSenderAccount('other@example.com');
    cubit.discardChanges();

    expect(cubit.state.provider, MailProviderId.gmail);
    expect(cubit.state.senderAccount, 'sender@example.com');
    expect(cubit.state.hasChanges, isFalse);
  });

  test('language is persisted immediately', () async {
    await cubit.selectLanguage(AppLanguage.el);

    expect((await repository.load()).language, AppLanguage.el);
    expect(cubit.state.saved!.language, AppLanguage.el);
  });

  test('gallery switch is persisted immediately', () async {
    await cubit.setSaveToGallery(true);

    expect((await repository.load()).saveToGallery, isTrue);
  });

  test('immediate changes keep the unsaved mail draft', () async {
    cubit.setSenderAccount('other@example.com');
    await cubit.setSaveToGallery(true);

    expect(cubit.state.senderAccount, 'other@example.com');
    expect(cubit.state.hasChanges, isTrue);
  });

  test('changeFolder stores the new folder', () async {
    const other = StorageFolder(
      uri: 'content://com.example.test/tree/primary%3AOther',
      name: 'Other',
    );
    picker.result = other;
    await cubit.changeFolder();

    expect((await repository.load()).storageFolder, other);
    expect(cubit.state.folderStatus, SettingsFolderStatus.idle);
  });

  test('cancelling the picker keeps the current folder', () async {
    picker.result = null;
    await cubit.changeFolder();

    expect((await repository.load()).storageFolder, testFolder);
    expect(cubit.state.folderStatus, SettingsFolderStatus.idle);
  });

  test('picker failure is reported and keeps the current folder', () async {
    picker.error = Exception('boom');
    await cubit.changeFolder();

    expect(cubit.state.folderStatus, SettingsFolderStatus.failed);
    expect((await repository.load()).storageFolder, testFolder);
  });

  test('lost folder access is detected and cleared by a new pick', () async {
    final lostPicker = FakeStorageFolderPicker()..accessGranted = false;
    final container = await buildTestContainer(picker: lostPicker);
    final repo = container<SettingsRepository>();
    await repo.save(
      (await repo.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
      ),
    );
    final lost = container<SettingsEditorCubit>();
    await lost.start();

    expect(lost.state.folderAccessLost, isTrue);

    lostPicker.accessGranted = true;
    await lost.changeFolder();
    expect(lost.state.folderAccessLost, isFalse);
    await lost.close();
  });
}
