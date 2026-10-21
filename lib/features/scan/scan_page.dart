import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import '../../domain/entities/captured_page.dart';
import '../../domain/entities/scan_mode.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../services/camera/camera_service.dart';
import 'scan_cubit.dart';
import 'scan_keys.dart';
import 'scan_state.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The camera is released in the background and reopened on return. Only
  /// `paused` counts: `inactive` also happens while the permission dialog is
  /// shown, and closing the camera then would break the first start.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cubit = context.read<ScanCubit>();
    if (state == AppLifecycleState.paused) {
      cubit.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      cubit.onForeground();
    }
  }

  Future<void> _confirmLeave() async {
    final strings = AppStrings.of(context);
    final cubit = context.read<ScanCubit>();
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.scanDiscardTitle),
        content: Text(strings.scanDiscardBody),
        actions: [
          TextButton(
            key: ScanKeys.dialogStay,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.settingsStay),
          ),
          TextButton(
            key: ScanKeys.dialogDiscard,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.settingsDiscard),
          ),
        ],
      ),
    );
    if (discard != true) return;
    await cubit.cancel();
    if (mounted) context.pop();
  }

  Future<void> _openSettings() async {
    final cubit = context.read<ScanCubit>();
    await context.push<void>(RoutePaths.settings);
    if (mounted) await cubit.retryAfterFolderFix();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ScanCubit, ScanState>(
      listenWhen: (previous, current) =>
          previous.phase != ScanPhase.saved && current.phase == ScanPhase.saved,
      listener: (context, state) {
        context.pushReplacement(RoutePaths.scanResult, extra: state.result);
      },
      builder: (context, state) {
        final saving = state.phase == ScanPhase.saving;
        return PopScope(
          canPop: !state.hasUnsavedPages && !saving,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !saving) _confirmLeave();
          },
          // Camera-app layout: the preview fills the screen and every control
          // floats above it, so nothing shrinks the picture.
          child: Scaffold(
            extendBodyBehindAppBar: true,
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black45,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              title: _ModeSelector(state: state),
            ),
            body: _Body(state: state, onSettings: _openSettings),
          ),
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.onSettings});

  final ScanState state;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _Viewfinder(state: state, onSettings: onSettings),
        _ControlsOverlay(state: state),
      ],
    );
  }
}

/// Single/Multi switch. It sits in the app bar, on a surface that stays
/// readable over any picture, in light and dark.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScanCubit>();
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SegmentedButton<ScanMode>(
          key: ScanKeys.modeSelector,
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: [
            ButtonSegment<ScanMode>(
              value: ScanMode.single,
              label: Text(strings.scanModeSingle),
            ),
            ButtonSegment<ScanMode>(
              value: ScanMode.multi,
              label: Text(strings.scanModeMulti),
            ),
          ],
          selected: <ScanMode>{state.mode},
          onSelectionChanged: state.canChangeMode
              ? (selection) => cubit.setMode(selection.first)
              : null,
        ),
      ),
    );
  }
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.state, required this.onSettings});

  final ScanState state;
  final VoidCallback onSettings;

  bool get _showsPreview => switch (state.phase) {
    ScanPhase.ready ||
    ScanPhase.capturing ||
    ScanPhase.saving ||
    ScanPhase.saveFailed => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<ScanCubit>();

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (_showsPreview)
          Center(
            key: ScanKeys.preview,
            child: context.read<CameraService>().buildPreview(context),
          ),
        if (state.phase == ScanPhase.starting)
          const Center(child: CircularProgressIndicator()),
        if (state.phase == ScanPhase.saving)
          Container(
            key: ScanKeys.saving,
            color: Colors.black54,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  strings.scanSaving,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        if (state.phase == ScanPhase.folderUnavailable)
          _Message(
            text: strings.homeFolderLostBanner,
            actions: [
              FilledButton(
                key: ScanKeys.folderOpenSettings,
                onPressed: onSettings,
                child: Text(strings.homeOpenSettings),
              ),
            ],
          ),
        if (state.phase == ScanPhase.permissionDenied)
          _Message(
            text: strings.scanPermissionDenied,
            actions: [
              FilledButton(
                key: ScanKeys.retryCamera,
                onPressed: cubit.retryCamera,
                child: Text(strings.scanRetry),
              ),
              OutlinedButton(
                key: ScanKeys.openAppSettings,
                onPressed: cubit.openAppSettings,
                child: Text(strings.scanOpenAppSettings),
              ),
            ],
          ),
        if (state.phase == ScanPhase.cameraUnavailable)
          _Message(
            text: strings.scanCameraUnavailable,
            actions: [
              FilledButton(
                key: ScanKeys.retryCamera,
                onPressed: cubit.retryCamera,
                child: Text(strings.scanRetry),
              ),
            ],
          ),
        if (state.phase == ScanPhase.saveFailed)
          _Message(
            text: strings.scanSaveFailed,
            actions: [
              FilledButton(
                key: ScanKeys.retrySave,
                onPressed: cubit.save,
                child: Text(strings.scanRetry),
              ),
            ],
          ),
        if (state.captureFailed)
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              key: ScanKeys.captureFailed,
              margin: EdgeInsets.fromLTRB(
                12,
                MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                12,
                12,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                strings.scanCaptureFailed,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Explanation plus buttons, on a surface that reads well in light and dark.
class _Message extends StatelessWidget {
  const _Message({required this.text, required this.actions});

  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurface),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 8, children: actions),
        ],
      ),
    );
    return Center(child: card);
  }
}

/// Small preview of a cached shot. A missing or unreadable file shows a
/// placeholder instead of failing.
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      cacheWidth: 192,
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Icon(Icons.image_outlined),
      ),
    );
  }
}

/// Translucent panel behind the floating controls.
const _panelColor = Colors.black54;

/// Capture, Done, delete-last and the thumbnails, floating over the preview.
/// Portrait: along the bottom. Landscape (wider than tall): on the right
/// side, stacked vertically, like a phone camera.
class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final showThumbnails = state.mode == ScanMode.multi && state.hasPages;
    final top = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final landscape = constraints.maxWidth > constraints.maxHeight;
        if (landscape) {
          return Padding(
            padding: EdgeInsets.only(top: top),
            child: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showThumbnails) _SideThumbnails(pages: state.pages),
                    _SideActions(state: state),
                  ],
                ),
              ),
            ),
          );
        }
        return SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showThumbnails) _BottomThumbnails(pages: state.pages),
                _BottomActions(state: state),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BottomThumbnails extends StatelessWidget {
  const _BottomThumbnails({required this.pages});

  final List<CapturedPage> pages;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      color: _panelColor,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 64,
              child: ListView.separated(
                key: ScanKeys.thumbnails,
                scrollDirection: Axis.horizontal,
                itemCount: pages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 48,
                    child: PageThumbnail(path: pages[index].path),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            strings.scanPageCount(pages.length),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _SideThumbnails extends StatelessWidget {
  const _SideThumbnails({required this.pages});

  final List<CapturedPage> pages;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      width: 88,
      color: _panelColor,
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Text(
            strings.scanPageCount(pages.length),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              key: ScanKeys.thumbnails,
              itemCount: pages.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 64,
                  child: PageThumbnail(path: pages[index].path),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<ScanCubit>();
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: strings.scanCaptureButton,
      child: GestureDetector(
        key: ScanKeys.capture,
        onTap: state.canCapture ? cubit.capture : null,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
            color: state.canCapture ? scheme.primary : Colors.white24,
          ),
        ),
      ),
    );
  }
}

class _DeleteLastButton extends StatelessWidget {
  const _DeleteLastButton({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<ScanCubit>();
    return IconButton(
      key: ScanKeys.deleteLast,
      tooltip: strings.scanDeleteLast,
      color: Colors.white,
      onPressed: state.phase == ScanPhase.ready ? cubit.deleteLast : null,
      icon: const Icon(Icons.undo),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<ScanCubit>();
    return FilledButton(
      key: ScanKeys.done,
      onPressed: state.canFinish ? cubit.finish : null,
      child: Text(strings.scanDone),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final multi = state.mode == ScanMode.multi && state.hasPages;
    return Container(
      color: _panelColor,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 96,
            child: multi ? _DeleteLastButton(state: state) : null,
          ),
          _CaptureButton(state: state),
          SizedBox(width: 96, child: multi ? _DoneButton(state: state) : null),
        ],
      ),
    );
  }
}

class _SideActions extends StatelessWidget {
  const _SideActions({required this.state});

  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final multi = state.mode == ScanMode.multi && state.hasPages;
    return Container(
      width: 120,
      color: _panelColor,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Center(
        // Scrolls instead of overflowing on very low windows.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (multi) ...[
                _DoneButton(state: state),
                const SizedBox(height: 12),
              ],
              _CaptureButton(state: state),
              if (multi) ...[
                const SizedBox(height: 12),
                _DeleteLastButton(state: state),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
