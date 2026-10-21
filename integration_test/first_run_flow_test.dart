import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/app/injection.dart';
import 'package:one_click_scan/data/datasources/shared_preferences_key_value_store.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/first_run/first_run_keys.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

/// Runs on a real Android emulator/device with the REAL SharedPreferences
/// plugin. The system folder picker (SAF UI) cannot be driven by
/// integration_test, so it is replaced by a fake here. The real picker is
/// covered by the manual checklist in docs/PHASE_0_VALIDATION.md.
///
/// Run on the Claude Code emulator only:
///   flutter test integration_test/first_run_flow_test.dart -d `<emulator-id>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('wizard completes, survives an app restart, and lands on home', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();

    Future<void> launch() async {
      final container = await buildContainer(
        config: testConfig,
        keyValueStore: SharedPreferencesKeyValueStore(preferences),
        folderPicker: FakeStorageFolderPicker(),
      );
      await tester.pumpWidget(OneClickScanApp(container: container));
      await tester.pumpAndSettle();
    }

    // --- First launch: wizard ---
    await launch();
    expect(find.text('Step 1 of 4'), findsOneWidget);

    await tester.tap(find.byKey(FirstRunKeys.next));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(FirstRunKeys.pickFolder));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FirstRunKeys.next));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Outlook'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FirstRunKeys.sender),
      'sender@example.com',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(FirstRunKeys.next));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(FirstRunKeys.next)); // Finish
    await tester.pumpAndSettle();

    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);

    // --- Simulated restart: brand new container, same real storage ---
    await tester.pumpWidget(const SizedBox.shrink());
    await launch();

    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    expect(find.byKey(FirstRunKeys.next), findsNothing);

    final container = await buildContainer(
      config: testConfig,
      keyValueStore: SharedPreferencesKeyValueStore(preferences),
      folderPicker: FakeStorageFolderPicker(),
    );
    final saved = await container<SettingsRepository>().load();
    expect(saved.firstRunCompleted, isTrue);
    expect(saved.mailProvider, MailProviderId.outlook);
    expect(saved.storageFolder, testFolder);
  });
}
