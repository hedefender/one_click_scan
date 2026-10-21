import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import '../../domain/entities/app_language.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../presentation/l10n/mail_provider_labels.dart';
import 'first_run_cubit.dart';
import 'first_run_keys.dart';
import 'first_run_state.dart';

class FirstRunPage extends StatelessWidget {
  const FirstRunPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return BlocConsumer<FirstRunCubit, FirstRunState>(
      listenWhen: (previous, current) =>
          !previous.completed && current.completed,
      listener: (context, state) => context.go(RoutePaths.home),
      builder: (context, state) {
        final cubit = context.read<FirstRunCubit>();
        final isFirst = state.step == FirstRunStep.welcome;
        final isLast = state.step == FirstRunStep.gallery;
        final busy = state.folderStatus == FolderPickStatus.picking;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              strings.wizardStepIndicator(
                state.step.index + 1,
                FirstRunStep.values.length,
              ),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: switch (state.step) {
                      FirstRunStep.welcome => _WelcomeStep(state: state),
                      FirstRunStep.folder => _FolderStep(state: state),
                      FirstRunStep.mail => _MailStep(state: state),
                      FirstRunStep.gallery => _GalleryStep(state: state),
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Row(
                    children: [
                      if (!isFirst)
                        OutlinedButton(
                          key: FirstRunKeys.back,
                          onPressed: cubit.back,
                          child: Text(strings.actionBack),
                        ),
                      const Spacer(),
                      FilledButton(
                        key: FirstRunKeys.next,
                        onPressed: busy ? null : cubit.next,
                        child: Text(
                          isLast ? strings.actionFinish : strings.actionNext,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(body, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 24),
      ],
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

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.state});

  final FirstRunState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<FirstRunCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(strings.welcomeTitle, strings.welcomeBody),
        Text(
          strings.languageLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<AppLanguage>(
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
          selected: <AppLanguage>{state.language},
          onSelectionChanged: (selection) =>
              cubit.selectLanguage(selection.first),
        ),
      ],
    );
  }
}

class _FolderStep extends StatelessWidget {
  const _FolderStep({required this.state});

  final FirstRunState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<FirstRunCubit>();
    final folder = state.folder;
    final busy = state.folderStatus == FolderPickStatus.picking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(strings.folderTitle, strings.folderBody),
        FilledButton.tonalIcon(
          key: FirstRunKeys.pickFolder,
          onPressed: busy ? null : cubit.pickFolder,
          icon: const Icon(Icons.folder_open),
          label: Text(
            folder == null ? strings.folderPick : strings.folderChange,
          ),
        ),
        if (folder != null) ...[
          const SizedBox(height: 12),
          Text(strings.folderSelected(folder.name)),
        ],
        if (state.showErrors &&
            state
                .errorsFor(FirstRunStep.folder)
                .contains(FirstRunError.folderMissing))
          _ErrorText(strings.folderRequired),
        if (state.folderStatus == FolderPickStatus.failed)
          _ErrorText(strings.folderPickFailed),
      ],
    );
  }
}

class _MailStep extends StatefulWidget {
  const _MailStep({required this.state});

  final FirstRunState state;

  @override
  State<_MailStep> createState() => _MailStepState();
}

class _MailStepState extends State<_MailStep> {
  late final TextEditingController _sender;
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    _sender = TextEditingController(text: widget.state.senderAccount);
    _custom = TextEditingController(text: widget.state.customDestination);
  }

  @override
  void dispose() {
    _sender.dispose();
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<FirstRunCubit>();
    final state = widget.state;
    final errors = state.showErrors
        ? state.errorsFor(FirstRunStep.mail)
        : const <FirstRunError>{};
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(strings.mailTitle, strings.mailBody),
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
        if (errors.contains(FirstRunError.providerMissing))
          _ErrorText(strings.providerRequired),
        const SizedBox(height: 20),
        TextField(
          key: FirstRunKeys.sender,
          controller: _sender,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: strings.senderLabel,
            border: const OutlineInputBorder(),
            errorText: errors.contains(FirstRunError.senderInvalid)
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
            key: FirstRunKeys.customDestination,
            controller: _custom,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: strings.customDestinationLabel,
              border: const OutlineInputBorder(),
              errorText: errors.contains(FirstRunError.customDestinationInvalid)
                  ? strings.invalidEmail
                  : null,
            ),
            onChanged: cubit.setCustomDestination,
          ),
        ],
      ],
    );
  }
}

class _GalleryStep extends StatelessWidget {
  const _GalleryStep({required this.state});

  final FirstRunState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<FirstRunCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(strings.galleryTitle, strings.galleryNote),
        SwitchListTile(
          key: FirstRunKeys.gallerySwitch,
          contentPadding: EdgeInsets.zero,
          title: Text(strings.galleryToggle),
          value: state.saveToGallery,
          onChanged: cubit.setSaveToGallery,
        ),
      ],
    );
  }
}
