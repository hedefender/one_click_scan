import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/lighting/flash_mode.dart';
import '../../domain/lighting/light_metric.dart';
import '../../domain/lighting/lighting_config.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../services/camera/camera_service.dart';
import '../scan/scan_keys.dart';
import 'light_diagnostics_cubit.dart';

/// Hidden screen (5 taps on the app name in Settings): the live light numbers
/// of the preview, the numbers of a test shot, the threshold, and the
/// "flash required" signal of the camera (not available through the plugin).
class LightDiagnosticsPage extends StatelessWidget {
  const LightDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cubit = context.read<LightDiagnosticsCubit>();
    return Scaffold(
      appBar: AppBar(title: Text(strings.lightDiagTitle)),
      body: BlocBuilder<LightDiagnosticsCubit, LightDiagnosticsState>(
        builder: (context, state) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.ready)
                SizedBox(
                  height: 160,
                  child: Center(
                    child: context.read<CameraService>().buildPreview(context),
                  ),
                ),
              const SizedBox(height: 8),
              Text(strings.lightDiagNote),
              const SizedBox(height: 16),
              _Block(
                key: ScanKeys.lightDiagLive,
                title: strings.lightDiagLive,
                metric: state.live,
                emptyText: '—',
              ),
              const SizedBox(height: 8),
              _Block(
                key: ScanKeys.lightDiagShot,
                title: strings.lightDiagLastShot,
                metric: state.lastShot,
                emptyText: strings.lightDiagNoShot,
              ),
              const SizedBox(height: 8),
              Text(
                '${strings.lightDiagThreshold}: '
                '${LightingConfig.minPaperLevel.toStringAsFixed(0)}',
              ),
              Text('${strings.lightDiagFlashSignal}: n/a'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  FilledButton(
                    key: ScanKeys.lightDiagTake,
                    onPressed: state.ready && !state.taking ? cubit.take : null,
                    child: Text(strings.lightDiagTake),
                  ),
                  if (state.hasFlash)
                    OutlinedButton.icon(
                      onPressed: cubit.cycleFlash,
                      icon: Icon(switch (state.flashMode) {
                        FlashMode.off => Icons.flash_off,
                        FlashMode.auto => Icons.flash_auto,
                        FlashMode.on => Icons.flash_on,
                      }),
                      label: Text(switch (state.flashMode) {
                        FlashMode.off => strings.flashOffLabel,
                        FlashMode.auto => strings.flashAutoLabel,
                        FlashMode.on => strings.flashOnLabel,
                      }),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    super.key,
    required this.title,
    required this.metric,
    required this.emptyText,
  });

  final String title;
  final LightMetric? metric;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final m = metric;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            if (m == null)
              Text(emptyText)
            else ...[
              Text('${strings.lightDiagPaper}: ${m.paper.toStringAsFixed(1)}'),
              Text(
                '${strings.lightDiagContrast}: '
                '${m.contrast.toStringAsFixed(1)}',
              ),
              Text(
                LightingConfig.isLowLight(m)
                    ? strings.lightDiagLowYes
                    : strings.lightDiagLowNo,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
