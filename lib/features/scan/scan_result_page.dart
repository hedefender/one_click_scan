import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/navigation/route_paths.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/entities/mail_send_mode.dart';
import '../../domain/entities/stored_scan.dart';
import '../../domain/mail/mail_outcome.dart';
import '../../domain/ports/draft_sharer.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/scan/scan_flow.dart';
import '../../domain/usecases/recognize_pages.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../presentation/state/settings_cubit.dart';
import '../../services/scan_files/scan_temp_store.dart';
import 'mail_send_cubit.dart';
import 'mail_send_state.dart';
import 'scan_keys.dart';
import 'scan_page.dart' show PageThumbnail;
import 'scan_result_args.dart';
import 'scan_flow_cubit.dart';
import 'scan_flow_state.dart';

/// Shows what was stored and the state of the PDF. The cached shots are kept
/// only to draw the thumbnails and are deleted when this screen is left; the
/// background reading of the pages (OCR) ends with it too. Needs a
/// [ScanResultCubit] above it.
class ScanResultPage extends StatefulWidget {
  const ScanResultPage({super.key, required this.args});

  final ScanResultArgs args;

  StoredScan get result => args.result;
  OcrSession? get ocr => args.ocr;

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage> {
  late final ScanTempStore _tempStore;

  @override
  void initState() {
    super.initState();
    _tempStore = context.read<ScanTempStore>();
  }

  @override
  void dispose() {
    widget.ocr?.dispose();
    _tempStore.delete([
      for (final picture in widget.result.pictures) picture.sourcePath,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final pictures = widget.result.pictures;
    final folderName =
        context.watch<SettingsCubit>().state.storageFolder?.name ??
        strings.homeNotSet;
    final pdfBusy = context.select<ScanFlowCubit, bool>(
      (cubit) => cubit.state.busy,
    );
    final discarded = context.select<ScanFlowCubit, bool>(
      (cubit) => cubit.state.discarded,
    );
    final mailBusy = context.select<MailSendCubit, bool>(
      (cubit) => cubit.state.busy,
    );
    final busy = pdfBusy || mailBusy;

    // While the PDF is being made, leaving would lose it: the reading and the
    // working copies end with this screen. While a mail is being sent, leaving
    // would cancel it: the Cancel button of the mail section is the way out.
    return BlocListener<ScanFlowCubit, ScanFlowViewState>(
      listenWhen: (previous, current) => previous.flow != current.flow,
      listener: (context, state) {
        final mail = context.read<MailSendCubit>();
        switch (state.flow) {
          case FlowAwaitingDecision(:final pdf):
            mail.attach(pdf);
          case FlowFinished(:final pdf, :final delivery):
            mail.adopt(pdf, delivery);
          case FlowCancelled(:final pdf) when pdf != null:
            mail.attach(pdf);
          case _:
            break;
        }
      },
      child: PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(title: Text(strings.scanResultTitle)),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    discarded
                        ? strings.discardDone
                        : strings.scanResultSummary(
                            pictures.length,
                            folderName,
                          ),
                    key: ScanKeys.resultSummary,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: ScanKeys.resultList,
                    children: [
                      const _PdfSection(),
                      const _FlowSection(),
                      const _MailSection(),
                      const _DiscardSection(),
                      if (!discarded)
                        for (final picture in pictures)
                          ListTile(
                            key: ScanKeys.resultFile(picture.fileName),
                            leading: SizedBox(
                              width: 48,
                              height: 48,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: PageThumbnail(path: picture.sourcePath),
                              ),
                            ),
                            title: Text(picture.fileName),
                            subtitle: _gallerySubtitle(context, picture),
                          ),
                    ],
                  ),
                ),
                if (widget.ocr != null && !discarded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: ScanKeys.resultOcr,
                        onPressed: () => context.push(
                          RoutePaths.ocrResult,
                          extra: widget.ocr,
                        ),
                        child: Text(strings.ocrOpenResult),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: ScanKeys.resultBack,
                      onPressed: busy
                          ? null
                          : () => context.go(RoutePaths.home),
                      child: Text(
                        pdfBusy
                            ? strings.pdfWait
                            : mailBusy
                            ? strings.mailSending
                            : strings.scanBackHome,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _gallerySubtitle(BuildContext context, StoredPicture picture) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return switch (picture.gallery) {
      GalleryCopyStatus.notRequested => null,
      GalleryCopyStatus.saved => Text(strings.scanGallerySaved),
      GalleryCopyStatus.failed => Text(
        strings.scanGalleryFailed,
        style: TextStyle(color: scheme.error),
      ),
    };
  }
}

/// The state of the PDF: text only, and a bar that moves when a page is done
/// (nothing here animates all the time).
class _PdfSection extends StatelessWidget {
  const _PdfSection();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<ScanFlowCubit, ScanFlowViewState>(
      builder: (context, state) {
        final cubit = context.read<ScanFlowCubit>();
        final flow = state.flow;
        final children = <Widget>[
          Text(strings.pdfTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
        ];
        switch (flow) {
          case null || FlowRecognizing():
            final read = flow is FlowRecognizing ? flow.read : 0;
            final total = flow is FlowRecognizing ? flow.total : 0;
            final inProgress = total == 0 ? 1 : (read + 1).clamp(1, total);
            children.addAll([
              Text(
                key: ScanKeys.pdfStatus,
                strings.pdfReading(inProgress, total),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: total == 0 ? 0 : read / total),
              const SizedBox(height: 8),
              TextButton(
                key: ScanKeys.pdfSkipText,
                onPressed: cubit.skipText,
                child: Text(strings.pdfSkipText),
              ),
            ]);
          case FlowBuildingPdf():
            children.add(Text(key: ScanKeys.pdfStatus, strings.pdfCreating));
          case FlowPdfFailed(:final failure):
            children.addAll([
              Text(
                key: ScanKeys.pdfFailure,
                _failureText(strings, failure),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: ScanKeys.pdfRetry,
                onPressed: cubit.retry,
                child: Text(strings.pdfRetry),
              ),
            ]);
          case _ when state.pdfStored:
            final pdf = state.pdf!;
            children.addAll([
              Text(key: ScanKeys.pdfStatus, strings.pdfSaved(pdf.fileName)),
              Text(
                key: ScanKeys.pdfDetails,
                strings.pdfDetails(pdf.pageCount, _size(pdf.byteSize)),
                style: theme.textTheme.bodySmall,
              ),
              if (pdf.pagesWithoutText > 0) ...[
                const SizedBox(height: 8),
                Text(
                  key: ScanKeys.pdfNoText,
                  strings.pdfPagesWithoutText(pdf.pagesWithoutText),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                key: ScanKeys.pdfNote,
                strings.pdfTextNote,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ScanKeys.pdfOpen,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(strings.pdfOpen),
                  onPressed: cubit.openPdf,
                ),
              ),
              if (state.openProblem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    key: ScanKeys.pdfOpenProblem,
                    state.openProblem == OpenPdfResult.noViewer
                        ? strings.pdfOpenNoViewer
                        : strings.pdfOpenFailed,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ]);
          case _:
            return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
      },
    );
  }

  static String _failureText(AppStrings strings, ScanPdfFailure? failure) {
    return switch (failure) {
      ScanPdfFailure.pageImageMissing => strings.pdfFailedImage,
      ScanPdfFailure.unsupported => strings.pdfFailedUnsupported,
      ScanPdfFailure.noAccess => strings.pdfFailedNoAccess,
      ScanPdfFailure.writeFailed => strings.pdfFailedWrite,
      ScanPdfFailure.buildFailed || null => strings.pdfFailedBuild,
    };
  }

  /// "812 KB" or "1.4 MB".
  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).ceil()} KB';
  }
}

/// What the flow is doing or has done that the other sections do not say: the
/// work in words (no spinner that never stops), the Cancel button, the
/// "cancelled" and "not sent" notes, the hint of the preview.
class _FlowSection extends StatelessWidget {
  const _FlowSection();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<ScanFlowCubit, ScanFlowViewState>(
      builder: (context, state) {
        final cubit = context.read<ScanFlowCubit>();
        final children = <Widget>[];
        switch (state.flow) {
          case FlowSending():
            children.add(Text(key: ScanKeys.flowStatus, strings.mailSending));
          case FlowSharing():
            children.add(Text(key: ScanKeys.flowStatus, strings.flowSharing));
          case FlowAwaitingDecision():
            children.addAll([
              Text(strings.previewTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(key: ScanKeys.flowStatus, strings.previewHint),
            ]);
          case FlowCancelled(:final stage):
            children.add(
              Text(
                key: ScanKeys.flowCancelled,
                stage == ScanFlowStage.sending
                    ? strings.flowCancelledSending
                    : strings.flowCancelledReading,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            );
          case FlowFinished(:final delivery) when delivery is DeliveryNotSent:
            children.addAll([
              Text(
                key: ScanKeys.flowNotSent,
                strings.flowNotSent,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 4),
              Text(strings.flowNotSentNote),
            ]);
          case _:
            break;
        }
        if (state.canCancel) {
          children.addAll([
            const SizedBox(height: 8),
            OutlinedButton(
              key: ScanKeys.flowCancel,
              onPressed: cubit.cancel,
              child: Text(strings.flowCancel),
            ),
          ]);
        }
        if (children.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
      },
    );
  }
}

/// "Discard" of the preview: asks first (the deletion cannot be undone), then
/// says what happened, and never says "deleted" while part of the scan is left.
class _DiscardSection extends StatelessWidget {
  const _DiscardSection();

  Future<void> _confirm(BuildContext context) async {
    final strings = AppStrings.of(context);
    final cubit = context.read<ScanFlowCubit>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.discardConfirmTitle),
        content: Text(strings.discardConfirmBody),
        actions: [
          TextButton(
            key: ScanKeys.discardKeep,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.discardConfirmNo),
          ),
          TextButton(
            key: ScanKeys.discardConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.discardConfirmYes),
          ),
        ],
      ),
    );
    if (yes == true) await cubit.discard();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    // Once the message went (or the e-mail app got the PDF) the choice is made:
    // the preview offers Send or Discard, not both.
    final handedOver = context.select<MailSendCubit, bool>(
      (cubit) =>
          cubit.state.phase == MailPhase.sent ||
          cubit.state.phase == MailPhase.sending ||
          cubit.state.draft == DraftShareResult.opened ||
          cubit.state.draft == DraftShareResult.openedGeneric,
    );
    return BlocBuilder<ScanFlowCubit, ScanFlowViewState>(
      builder: (context, state) {
        final outcome = state.discardOutcome;
        final children = <Widget>[];
        if (state.discard == DiscardPhase.running) {
          children.add(
            Text(key: ScanKeys.discardStatus, strings.discardRunning),
          );
        } else if (outcome != null && !outcome.complete) {
          children.add(
            Text(
              key: ScanKeys.discardStatus,
              strings.discardPartial(
                outcome.picturesLeft,
                outcome.pdfLeft,
                outcome.galleryLeft,
              ),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          );
        }
        if (state.canDiscard && !handedOver) {
          children.addAll([
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: ScanKeys.discard,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirm(context),
              label: Text(strings.previewDiscard),
            ),
          ]);
        }
        if (children.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
      },
    );
  }
}

/// Sends the stored PDF by e-mail, by hand: a button, then a state in words
/// (no spinner that never stops). Shown once the PDF is stored.
class _MailSection extends StatelessWidget {
  const _MailSection();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    // Not while the flow is still working (sending, opening the e-mail app):
    // the flow says that, and this section takes over when it has ended.
    final saved = context.select<ScanFlowCubit, bool>(
      (cubit) =>
          cubit.state.pdfStored &&
          switch (cubit.state.flow) {
            FlowAwaitingDecision() || FlowFinished() => true,
            FlowCancelled(:final pdf) => pdf != null,
            _ => false,
          },
    );
    if (!saved) return const SizedBox.shrink();
    final settings = context.watch<SettingsCubit>().state;
    return BlocBuilder<MailSendCubit, MailSendState>(
      builder: (context, state) {
        final cubit = context.read<MailSendCubit>();
        final error = TextStyle(color: theme.colorScheme.error);
        final sharing = state.mode == MailSendMode.shareDraft;
        final destination = settings.effectiveDestination;
        final children = <Widget>[
          Text(strings.mailSendTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
        ];
        switch (state.phase) {
          case MailPhase.idle:
            children.add(
              Text(
                key: ScanKeys.mailNote,
                sharing
                    ? strings.mailShareNote
                    : destination == null
                    ? strings.mailNotConfiguredAccount
                    : strings.mailSendTo(destination),
              ),
            );
            children.add(const SizedBox(height: 12));
            children.add(
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ScanKeys.mailSend,
                  icon: Icon(sharing ? Icons.open_in_new : Icons.send),
                  label: Text(
                    sharing ? strings.mailShareButton : strings.mailSendButton,
                  ),
                  onPressed: cubit.send,
                ),
              ),
            );
          case MailPhase.sending:
            children.addAll([
              Text(key: ScanKeys.mailStatus, strings.mailSending),
              const SizedBox(height: 8),
              OutlinedButton(
                key: ScanKeys.mailCancel,
                onPressed: cubit.cancel,
                child: Text(strings.mailCancel),
              ),
            ]);
          case MailPhase.sent:
            children.add(Text(key: ScanKeys.mailStatus, strings.mailSent));
          case MailPhase.failed:
            children.addAll([
              Text(
                key: ScanKeys.mailFailure,
                _failureText(strings, state.outcome, settings.mailProvider),
                style: error,
              ),
              // The step and the reply code, so the user can say what
              // happened without giving any data.
              if (state.outcome?.stage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    key: ScanKeys.mailDiagnostic,
                    strings.mailDiagnostic(
                      state.outcome!.stage!,
                      state.outcome!.replyCode,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              if (state.offersFallback(settings.mailProvider)) ...[
                Text(
                  key: ScanKeys.mailFallbackReason,
                  settings.mailProvider == MailProviderId.outlook
                      ? strings.mailFallbackReasonOutlook
                      : strings.mailFallbackReasonAuth,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: ScanKeys.mailFallback,
                  icon: const Icon(Icons.open_in_new),
                  onPressed: cubit.useShareMode,
                  label: Text(strings.mailFallbackButton),
                ),
                const SizedBox(height: 8),
              ],
              if (state.outcome is MailAuthFailed &&
                  settings.mailProvider != MailProviderId.outlook) ...[
                OutlinedButton(
                  key: ScanKeys.mailGuide,
                  onPressed: () => context.push(RoutePaths.settings),
                  child: Text(strings.mailGuideOpenSettings),
                ),
                const SizedBox(height: 8),
              ],
              if (state.needsSettings)
                FilledButton(
                  key: ScanKeys.mailOpenSettings,
                  onPressed: () => context.push(RoutePaths.settings),
                  child: Text(strings.mailOpenSettings),
                )
              else
                OutlinedButton(
                  key: ScanKeys.mailRetry,
                  onPressed: cubit.send,
                  child: Text(strings.mailRetry),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: ScanKeys.mailOpenApp,
                icon: const Icon(Icons.open_in_new),
                onPressed: cubit.openMailApp,
                label: Text(strings.mailOpenApp),
              ),
            ]);
        }
        final draft = state.draft;
        if (draft != null) {
          children.addAll([
            const SizedBox(height: 8),
            Text(
              key: ScanKeys.mailDraft,
              switch (draft) {
                DraftShareResult.opened => strings.mailDraftOpened,
                DraftShareResult.openedGeneric =>
                  strings.mailDraftOpenedGeneric,
                DraftShareResult.noApp => strings.mailDraftNoApp,
                DraftShareResult.failed => strings.mailDraftFailed,
              },
              style:
                  draft == DraftShareResult.opened ||
                      draft == DraftShareResult.openedGeneric
                  ? null
                  : error,
            ),
          ]);
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
      },
    );
  }

  static String _failureText(
    AppStrings strings,
    MailOutcome? outcome,
    MailProviderId? provider,
  ) {
    return switch (outcome) {
      MailNotConfigured(:final reason) =>
        reason == MailNotConfiguredReason.password
            ? strings.mailNotConfiguredPassword
            : strings.mailNotConfiguredAccount,
      MailAuthFailed() =>
        provider == MailProviderId.outlook
            ? '${strings.mailFailedAuth}\n${strings.mailOutlookWarning}'
            : strings.mailFailedAuth,
      MailNetworkError() => strings.mailFailedNetwork,
      MailTooLarge() => strings.mailFailedTooLarge,
      // The code is in the diagnostic line, not in the sentence.
      MailRejected() => strings.mailFailedRejected(0),
      _ => strings.mailFailedUnknown,
    };
  }
}
