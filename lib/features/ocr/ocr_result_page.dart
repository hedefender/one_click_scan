import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/ocr_line.dart';
import '../../domain/entities/ocr_outcome.dart';
import '../../domain/entities/ocr_progress.dart';
import '../../domain/entities/ocr_result.dart';
import '../../domain/usecases/recognize_pages.dart';
import '../../presentation/l10n/app_strings.dart';
import 'ocr_boxes_painter.dart';
import 'ocr_keys.dart';
import 'ocr_result_cubit.dart';

/// The check screen of the OCR (not the final UX, which has no text screen):
/// progress as text while a page is read, then the text of every line with its
/// confidence and geometry, and the numbers of the run.
///
/// Nothing here animates continuously: the progress bar is determinate and
/// only moves when a line is done (a spinner raised the UI load and slowed
/// the reading on the phone).
class OcrResultPage extends StatelessWidget {
  const OcrResultPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return BlocBuilder<OcrResultCubit, OcrResultState>(
      builder: (context, state) {
        final page = state.page;
        return Scaffold(
          appBar: AppBar(title: Text(strings.ocrResultTitle)),
          body: SafeArea(
            child: Column(
              children: [
                if (state.pageCount > 1) _PageSwitcher(state: state),
                Expanded(
                  child: page == null
                      ? const SizedBox.shrink()
                      : _PageBody(
                          page: page,
                          packId: state.snapshot.packId,
                          // The switch state lives below, so another page
                          // starts with its own default.
                          key: ValueKey(page.key),
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

class _PageSwitcher extends StatelessWidget {
  const _PageSwitcher({required this.state});

  final OcrResultState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<OcrResultCubit>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: OcrKeys.previousPage,
          icon: const Icon(Icons.chevron_left),
          onPressed: state.hasPrevious ? cubit.previous : null,
        ),
        Text(
          key: OcrKeys.pageLabel,
          strings.ocrPageOf(state.pageIndex + 1, state.pageCount),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          key: OcrKeys.nextPage,
          icon: const Icon(Icons.chevron_right),
          onPressed: state.hasNext ? cubit.next : null,
        ),
      ],
    );
  }
}

class _PageBody extends StatefulWidget {
  const _PageBody({super.key, required this.page, required this.packId});

  final OcrPageState page;
  final String packId;

  @override
  State<_PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<_PageBody> {
  var _showBoxes = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final page = widget.page;
    final outcome = page.outcome;
    final result = outcome is OcrSuccess ? outcome.result : null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (outcome == null)
                _Status(page: page)
              else if (outcome is! OcrSuccess)
                _Failure(outcome: outcome),
              if (result != null) ...[
                _Summary(page: page, result: result),
                SwitchListTile(
                  key: OcrKeys.showBoxes,
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.ocrShowBoxes),
                  value: _showBoxes,
                  onChanged: page.image == null
                      ? null
                      : (value) => setState(() => _showBoxes = value),
                ),
                if (_showBoxes && page.image != null)
                  _BoxesImage(page: page, result: result),
                const SizedBox(height: 8),
                if (result.lines.isEmpty)
                  Text(key: OcrKeys.noText, strings.ocrNoText)
                else
                  Column(
                    key: OcrKeys.lines,
                    children: [
                      for (var i = 0; i < result.lines.length; i++)
                        _LineTile(index: i, line: result.lines[i]),
                    ],
                  ),
              ],
            ],
          ),
        ),
        if (result != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: OcrKeys.copy,
                icon: const Icon(Icons.copy),
                label: Text(strings.ocrCopy),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Clipboard.setData(ClipboardData(text: result.text));
                  messenger.showSnackBar(
                    SnackBar(content: Text(strings.ocrCopied)),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// "Reading line 12 of 51" and a bar that only moves when a line is done.
class _Status extends StatelessWidget {
  const _Status({required this.page});

  final OcrPageState page;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final progress = page.progress;
    final text = switch (page.status) {
      OcrPageStatus.queued => strings.ocrStatusQueued,
      OcrPageStatus.preparing => strings.ocrStatusPreparing,
      _ => switch (progress?.stage) {
        OcrStage.loadingModels => strings.ocrStatusLoadingModels,
        OcrStage.preparingImage => strings.ocrStatusPreparing,
        OcrStage.recognizing => strings.ocrStatusRecognizing(
          progress!.done,
          progress.total,
        ),
        _ => strings.ocrStatusDetecting,
      },
    };
    final fraction = progress != null && progress.total > 0
        ? progress.done / progress.total
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: OcrKeys.status,
          text,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(key: OcrKeys.progressBar, value: fraction),
      ],
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.outcome});

  final OcrOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final text = switch (outcome) {
      OcrSuccess() => '',
      OcrTimedOut() => strings.ocrTimedOut,
      OcrCancelled() => strings.ocrCancelled,
      OcrFailed(:final reason) => switch (reason) {
        OcrFailureReason.modelUnavailable => strings.ocrFailedModel,
        OcrFailureReason.imageUnreadable => strings.ocrFailedImage,
        OcrFailureReason.imageTooLarge => strings.ocrFailedTooLarge,
        OcrFailureReason.unsupported => strings.ocrFailedUnsupported,
        OcrFailureReason.engineError => strings.ocrFailedEngine,
      },
    };
    return Text(
      key: OcrKeys.failure,
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.page, required this.result});

  final OcrPageState page;
  final OcrResult result;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final image = page.image;
    final seconds = (result.duration.inMilliseconds / 1000).toStringAsFixed(1);
    final style = Theme.of(context).textTheme.bodyMedium;
    return Card(
      key: OcrKeys.summary,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.ocrSummaryPack(strings.ocrPackName(result.packId)),
              style: style,
            ),
            Text(strings.ocrSummaryDuration(seconds), style: style),
            Text(
              strings.ocrSummaryWorkImage(
                result.imageWidth,
                result.imageHeight,
              ),
              style: style,
            ),
            if (image != null)
              Text(
                strings.ocrSummaryCapture(
                  image.sourceWidth,
                  image.sourceHeight,
                  image.sourceMegapixels.toStringAsFixed(1),
                ),
                style: style,
              ),
            Text(
              strings.ocrSummaryBoxes(result.boxCount, result.filteredCount),
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}

class _BoxesImage extends StatelessWidget {
  const _BoxesImage({required this.page, required this.result});

  final OcrPageState page;
  final OcrResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      key: OcrKeys.boxesImage,
      aspectRatio: result.imageWidth / result.imageHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(page.image!.path),
            fit: BoxFit.fill,
            cacheWidth: 1200,
            // The working copy may be gone (the screen is being left).
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
          CustomPaint(
            painter: OcrBoxesPainter(
              lines: result.lines,
              keptColor: scheme.primary,
              filteredColor: scheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.index, required this.line});

  final int index;
  final OcrLine line;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final filtered = line.filtered;
    final top = line.quad[0];
    final subtitle = StringBuffer(
      '${(line.confidence * 100).round()}%'
      ' · (${top.x.toStringAsFixed(2)}, ${top.y.toStringAsFixed(2)})',
    );
    if (filtered) subtitle.write(' · ${strings.ocrFilteredLabel}');
    return ListTile(
      key: OcrKeys.line(index),
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        line.text,
        style: filtered
            ? TextStyle(
                color: scheme.error,
                decoration: TextDecoration.lineThrough,
              )
            : null,
      ),
      subtitle: Text(
        subtitle.toString(),
        style: filtered ? TextStyle(color: scheme.error) : null,
      ),
    );
  }
}
