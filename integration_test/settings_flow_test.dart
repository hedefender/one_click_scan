import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/app/injection.dart';
import 'package:one_click_scan/data/datasources/shared_preferences_key_value_store.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/first_run/first_run_keys.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

/// Runs on a real Android emulator/device with the REAL SharedPreferences
/// plugin and a fake folder picker (the system picker UI cannot be driven by
/// integration_test; it is covered by docs/PHASE_0_5_VALIDATION.md).
///
/// Run on the Claude Code emulator only:
///   flutter test integration_test/settings_flow_test.dart -d `<emulator-id>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('wizard, then settings: an email change survives a restart', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();

    Future<GetIt> launch() async {
      final container = await buildContainer(
        config: testConfig,
        keyValueStore: SharedPreferencesKeyValueStore(preferences),
        folderPicker: FakeStorageFolderPicker(),
      );
      await tester.pumpWidget(OneClickScanApp(container: container));
      await tester.pumpAndSettle();
      return container;
    }

    Future<void> tapKey(Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.tap(find.byKey(key));
      await tester.pumpAndSettle();
    }

    // --- Wizard ---
    await launch();
    await tapKey(FirstRunKeys.next); // welcome
    await tapKey(FirstRunKeys.pickFolder);
    await tapKey(FirstRunKeys.next); // folder
    await tester.tap(find.text('Gmail'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FirstRunKeys.sender),
      'sender@example.com',
    );
    await tester.pumpAndSettle();
    await tapKey(FirstRunKeys.next); // mail
    await tapKey(FirstRunKeys.next); // gallery
    await tapKey(FirstRunKeys.flowPreview);
    await tapKey(FirstRunKeys.next); // finish
    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);

    // --- Settings: change the email ---
    await tapKey(HomeKeys.settings);
    await tester.enterText(find.byKey(SettingsKeys.sender), 'invalid');
    await tester.pumpAndSettle();
    expect(find.text('Invalid email address.'), findsOneWidget);

    await tester.enterText(
      find.byKey(SettingsKeys.sender),
      'changed@example.com',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(SettingsKeys.save));
    await tester.pumpAndSettle();
    await tapKey(SettingsKeys.save);
    expect(find.text('Settings saved.'), findsOneWidget);

    // --- Simulated restart: new container, same real storage ---
    await tester.pumpWidget(const SizedBox.shrink());
    final restarted = await launch();

    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    expect(find.text('changed@example.com'), findsOneWidget);
    final saved = await restarted<SettingsRepository>().load();
    expect(saved.senderAccount, 'changed@example.com');
  });
}
