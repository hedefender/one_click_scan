import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import '../../domain/entities/app_settings.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../presentation/l10n/mail_provider_labels.dart';
import '../../presentation/state/settings_cubit.dart';
import 'home_cubit.dart';
import 'home_keys.dart';

/// Home screen. SCAN & SEND opens the camera (Phase 1); sending is wired up
/// in later phases.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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

  /// Access can be revoked while the app is in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<HomeCubit>().checkFolderAccess();
    }
  }

  Future<void> _openSettings() async {
    final cubit = context.read<HomeCubit>();
    await context.push<void>(RoutePaths.settings);
    if (mounted) await cubit.checkFolderAccess();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [
          IconButton(
            key: HomeKeys.settings,
            tooltip: strings.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<SettingsCubit, AppSettings>(
          builder: (context, settings) {
            final folderLost = context.watch<HomeCubit>().state;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (folderLost) ...[
                  MaterialBanner(
                    key: HomeKeys.folderLostBanner,
                    leading: const Icon(Icons.warning_amber_rounded),
                    content: Text(strings.homeFolderLostBanner),
                    actions: [
                      TextButton(
                        key: HomeKeys.folderLostAction,
                        onPressed: _openSettings,
                        child: Text(strings.homeOpenSettings),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: HomeKeys.scanAndSend,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(72),
                  ),
                  onPressed: () => context.push<void>(RoutePaths.scan),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(strings.homeScanAndSend),
                ),
                const SizedBox(height: 32),
                _InfoTile(
                  icon: Icons.folder_outlined,
                  label: strings.homeFolderLabel,
                  value: settings.storageFolder?.name ?? strings.homeNotSet,
                ),
                _InfoTile(
                  icon: Icons.mail_outline,
                  label: strings.homeProviderLabel,
                  value: settings.mailProvider?.label ?? strings.homeNotSet,
                ),
                _InfoTile(
                  icon: Icons.send_outlined,
                  label: strings.homeRecipientLabel,
                  value: settings.effectiveDestination ?? strings.homeNotSet,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
