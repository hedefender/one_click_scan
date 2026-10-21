import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/app_settings.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../presentation/l10n/mail_provider_labels.dart';
import '../../presentation/state/settings_cubit.dart';
import 'home_keys.dart';

/// Phase 0 placeholder. The SCAN & SEND button is wired up in later phases.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.appTitle)),
      body: SafeArea(
        child: BlocBuilder<SettingsCubit, AppSettings>(
          builder: (context, settings) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: HomeKeys.scanAndSend,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(72),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(strings.homeComingSoon)),
                    );
                  },
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
