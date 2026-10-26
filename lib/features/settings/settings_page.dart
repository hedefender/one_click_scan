import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/app_language.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/entities/mail_send_mode.dart';
import '../../domain/mail/mail_provider.dart';
import '../../domain/ocr/ocr_language_pack_registry.dart';
import '../../domain/validation/mail_settings_validation.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../presentation/l10n/mail_provider_labels.dart';
import 'settings_editor_cubit.dart';
import 'settings_editor_state.dart';
import 'settings_keys.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _confirmLeave(BuildContext context) async {
    final strings = AppStrings.of(context);
    final cubit = context.read<SettingsEditorCubit>();
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.settingsUnsavedTitle),
        content: Text(strings.settingsUnsavedBody),
        actions: [
          TextButton(
            key: SettingsKeys.dialogStay,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.settingsStay),
          ),
          TextButton(
            key: SettingsKeys.dialogDiscard,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.settingsDiscard),
          ),
        ],
      ),
    );
    if (discard != true) return;
    cubit.discardChanges();
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return BlocConsumer<SettingsEditorCubit, SettingsEditorState>(
      listenWhen: (previous, current) =>
          (!previous.justSaved && current.justSaved) ||
          (previous.passwordNotice != current.passwordNotice &&
              current.passwordNotice != MailPasswordNotice.none),
      listener: (context, state) {
        final text = switch (state.passwordNotice) {
          MailPasswordNotice.deleted => strings.mailPasswordDeleted,
          MailPasswordNotice.deleteFailed => strings.mailPasswordDeleteFailed,
          MailPasswordNotice.none => strings.settingsSaved,
        };
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
      },
      builder: (context, state) {
        return PopScope(
          canPop: !state.hasChanges,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave(context);
          },
          child: Scaffold(
            appBar: AppBar(title: Text(strings.settingsTitle)),
            body: SafeArea(
              child: state.isLoaded
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        _LanguageSection(state: state),
                        const SizedBox(height: 32),
                        _FolderSection(state: state),
                        const SizedBox(height: 32),
                        _MailSection(state: state),
                        const SizedBox(height: 32),
                        _GallerySection(state: state),
                        const SizedBox(height: 32),
                        _OcrSection(state: state),
                        const SizedBox(height: 32),
                        const _LicensesSection(),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _LanguageSection extends StatelessWidget {
  const _LanguageSection({required this.state});

  final SettingsEditorState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<SettingsEditorCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(strings.languageLabel),
        SegmentedButton<AppLanguage>(
          key: SettingsKeys.language,
          segments: const [
            ButtonSegment<AppLanguage>(
              value: AppLanguage.el,
              label: Text('Ελληνικά'),
            ),
            ButtonSegment<AppLanguage>(
              value: AppLanguage.en,
              label: Text('English'),
            ),
          ],
          selected: <AppLanguage>{state.saved!.language},
          onSelectionChanged: (selection) =>
              cubit.selectLanguage(selection.first),
        ),
      ],
    );
  }
}

class _FolderSection extends StatelessWidget {
  const _FolderSection({required this.state});

  final SettingsEditorState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<SettingsEditorCubit>();
    final folder = state.saved!.storageFolder;
    final busy = state.folderStatus == SettingsFolderStatus.picking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(strings.folderTitle),
        Text(
          folder == null
              ? strings.homeNotSet
              : strings.folderSelected(folder.name),
        ),
        if (state.folderAccessLost)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              key: SettingsKeys.folderAccessWarning,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.settingsFolderAccessLost,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            key: SettingsKeys.changeFolder,
            onPressed: busy ? null : cubit.changeFolder,
            icon: const Icon(Icons.folder_open),
            label: Text(strings.folderChange),
          ),
        ),
        if (state.folderStatus == SettingsFolderStatus.failed)
          _ErrorText(strings.folderPickFailed),
      ],
    );
  }
}

class _MailSection extends StatefulWidget {
  const _MailSection({required this.state});

  final SettingsEditorState state;

  @override
  State<_MailSection> createState() => _MailSectionState();
}

class _MailSectionState extends State<_MailSection> {
  late final TextEditingController _sender;
  late final TextEditingController _custom;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    _sender = TextEditingController(text: widget.state.senderAccount);
    _custom = TextEditingController(text: widget.state.customDestination);
    _password = TextEditingController(text: widget.state.password);
  }

  @override
  void dispose() {
    _sender.dispose();
    _custom.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Keeps the fields in step with the draft when it is reset from outside
  /// (discard). While typing the texts already match, so this is a no-op.
  void _syncControllers(SettingsEditorState state) {
    if (_sender.text != state.senderAccount) {
      _sender.text = state.senderAccount;
    }
    if (_custom.text != state.customDestination) {
      _custom.text = state.customDestination;
    }
    if (_password.text != state.password) {
      _password.text = state.password;
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncControllers(widget.state);
    final strings = AppStrings.of(context);
    final cubit = context.read<SettingsEditorCubit>();
    final state = widget.state;
    final errors = state.errors;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(strings.mailTitle),
        Text(strings.providerLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<MailProviderId>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          segments: [
            for (final provider in MailProviderId.values)
              ButtonSegment<MailProviderId>(
                value: provider,
                label: Text(provider.label),
              ),
          ],
          selected: state.provider == null
              ? <MailProviderId>{}
              : <MailProviderId>{state.provider!},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) cubit.selectProvider(selection.first);
          },
        ),
        if (errors.contains(MailSettingsError.providerMissing))
          _ErrorText(strings.providerRequired),
        const SizedBox(height: 20),
        TextField(
          key: SettingsKeys.sender,
          controller: _sender,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: strings.senderLabel,
            border: const OutlineInputBorder(),
            errorText: errors.contains(MailSettingsError.senderInvalid)
                ? strings.invalidEmail
                : null,
          ),
          onChanged: cubit.setSenderAccount,
        ),
        const SizedBox(height: 20),
        Text(strings.destinationLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<DestinationMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment<DestinationMode>(
              value: DestinationMode.own,
              label: Text(strings.destinationOwn),
            ),
            ButtonSegment<DestinationMode>(
              value: DestinationMode.custom,
              label: Text(strings.destinationCustom),
            ),
          ],
          selected: <DestinationMode>{state.destinationMode},
          onSelectionChanged: (selection) =>
              cubit.selectDestinationMode(selection.first),
        ),
        if (state.destinationMode == DestinationMode.custom) ...[
          const SizedBox(height: 16),
          TextField(
            key: SettingsKeys.customDestination,
            controller: _custom,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: strings.customDestinationLabel,
              border: const OutlineInputBorder(),
              errorText:
                  errors.contains(MailSettingsError.customDestinationInvalid)
                  ? strings.invalidEmail
                  : null,
            ),
            onChanged: cubit.setCustomDestination,
          ),
        ],
        const SizedBox(height: 20),
        _PasswordBlock(
          state: state,
          controller: _password,
          support: state.provider == null
              ? null
              : context
                    .read<MailProviderRegistry>()
                    .resolve(state.provider!)
                    .appPasswordSupport,
        ),
        const SizedBox(height: 20),
        Text(strings.mailModeTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<MailSendMode>(
          key: SettingsKeys.sendMode,
          showSelectedIcon: false,
          segments: [
            ButtonSegment<MailSendMode>(
              value: MailSendMode.sendNow,
              label: Text(strings.mailModeSend),
            ),
            ButtonSegment<MailSendMode>(
              value: MailSendMode.shareDraft,
              label: Text(strings.mailModeShare),
            ),
          ],
          selected: <MailSendMode>{state.saved!.mailSendMode},
          onSelectionChanged: (selection) =>
              cubit.selectSendMode(selection.first),
        ),
        const SizedBox(height: 8),
        Text(strings.mailModeShareNote, style: theme.textTheme.bodySmall),
        const SizedBox(height: 20),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: SettingsKeys.save,
            onPressed: state.canSave ? cubit.save : null,
            child: Text(strings.settingsSaveButton),
          ),
        ),
      ],
    );
  }
}

class _GallerySection extends StatelessWidget {
  const _GallerySection({required this.state});

  final SettingsEditorState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<SettingsEditorCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(strings.galleryTitle),
        Text(
          strings.galleryNote,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        SwitchListTile(
          key: SettingsKeys.gallerySwitch,
          contentPadding: EdgeInsets.zero,
          title: Text(strings.galleryToggle),
          value: state.saved!.saveToGallery,
          onChanged: cubit.setSaveToGallery,
        ),
      ],
    );
  }
}

/// The OCR language pack. The choice is explicit: the scanner never guesses
/// the language, and a wrong pack reads a page badly.
class _OcrSection extends StatelessWidget {
  const _OcrSection({required this.state});

  final SettingsEditorState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<SettingsEditorCubit>();
    final registry = context.read<OcrLanguagePackRegistry>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(strings.ocrSettingsTitle),
        Text(
          strings.ocrSettingsNote,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        RadioGroup<String>(
          groupValue: state.saved!.ocrPackId,
          onChanged: (id) {
            if (id != null) cubit.selectOcrPack(id);
          },
          child: Column(
            children: [
              for (final pack in registry.bundled)
                RadioListTile<String>(
                  key: SettingsKeys.ocrPack(pack.id),
                  contentPadding: EdgeInsets.zero,
                  value: pack.id,
                  title: Text(strings.ocrPackName(pack.id)),
                  subtitle: Text(strings.ocrPackDescription(pack.id)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LicensesSection extends StatelessWidget {
  const _LicensesSection();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return ListTile(
      key: SettingsKeys.licenses,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.description_outlined),
      title: Text(strings.licensesOpen),
      onTap: () =>
          showLicensePage(context: context, applicationName: strings.appTitle),
    );
  }
}

/// The app password, the instructions to make one, the connection test and
/// the way to delete the stored password. The password is a hidden field with
/// a button that shows it; it is written to secure storage only by Save.
class _PasswordBlock extends StatelessWidget {
  const _PasswordBlock({
    required this.state,
    required this.controller,
    required this.support,
  });

  final SettingsEditorState state;
  final TextEditingController controller;
  final AppPasswordSupport? support;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<SettingsEditorCubit>();
    final theme = Theme.of(context);
    final provider = state.provider;
    final error = TextStyle(color: theme.colorScheme.error);
    final testing = state.mailTest == MailTestStatus.running;
    final testText = switch (state.mailTest) {
      MailTestStatus.idle => null,
      MailTestStatus.running => strings.mailTestRunning,
      MailTestStatus.ok => strings.mailTestOk,
      MailTestStatus.needsPassword => strings.mailTestNeedsPassword,
      MailTestStatus.authFailed => strings.mailFailedAuth,
      MailTestStatus.network => strings.mailFailedNetwork,
      MailTestStatus.rejected => strings.mailFailedRejected(state.mailTestCode),
      MailTestStatus.unknown => strings.mailFailedUnknown,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: SettingsKeys.password,
          controller: controller,
          obscureText: !state.passwordVisible,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            labelText: strings.mailPasswordLabel,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              key: SettingsKeys.passwordToggle,
              tooltip: state.passwordVisible
                  ? strings.mailPasswordHide
                  : strings.mailPasswordShow,
              icon: Icon(
                state.passwordVisible ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: cubit.togglePasswordVisible,
            ),
          ),
          onChanged: cubit.setPassword,
        ),
        const SizedBox(height: 8),
        Text(
          key: SettingsKeys.passwordStatus,
          state.hasStoredPassword
              ? strings.mailPasswordStored
              : strings.mailPasswordNone,
          style: theme.textTheme.bodyMedium,
        ),
        Text(strings.mailPasswordPrivacy, style: theme.textTheme.bodySmall),
        if (support == AppPasswordSupport.unconfirmed) ...[
          const SizedBox(height: 8),
          Text(
            key: SettingsKeys.providerWarning,
            strings.mailOutlookWarning,
            style: error,
          ),
        ],
        if (provider != null)
          ExpansionTile(
            key: SettingsKeys.help,
            tilePadding: EdgeInsets.zero,
            title: Text(strings.mailHelpTitle),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, step)
                        in strings.mailHelpSteps(provider).indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('${i + 1}. $step'),
                      ),
                    if (strings.mailHelpNote(provider) != null &&
                        support != AppPasswordSupport.unconfirmed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          strings.mailHelpNote(provider)!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: SettingsKeys.mailTest,
              icon: const Icon(Icons.wifi_tethering),
              onPressed:
                  testing ||
                      provider == null ||
                      state.errors.contains(MailSettingsError.senderInvalid)
                  ? null
                  : cubit.testConnection,
              label: Text(strings.mailTest),
            ),
            if (state.hasStoredPassword)
              OutlinedButton.icon(
                key: SettingsKeys.passwordDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: cubit.deletePassword,
                label: Text(strings.mailPasswordDelete),
              ),
          ],
        ),
        if (testText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              key: SettingsKeys.mailTestResult,
              testText,
              style: switch (state.mailTest) {
                MailTestStatus.ok || MailTestStatus.running => null,
                _ => error,
              },
            ),
          ),
      ],
    );
  }
}
