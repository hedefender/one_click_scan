import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/services/about/about_services.dart';

/// Phase 6.5: the two native methods of About on the emulator. The emulator
/// may have an e-mail app or not: `composeMail` answers true or false and
/// never crashes.
///
///   tool/run_integration_test.sh `<claude-code-emulator>` \
///     integration_test/about_native_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('appInfo: version, build and Android release come back', (
    tester,
  ) async {
    final info = await AndroidAppInfoSource().read();

    expect(info, isNotNull);
    expect(info!.versionName, '0.1.0');
    expect(info.buildNumber, isNotEmpty);
    expect(int.tryParse(info.buildNumber), isNotNull);
    expect(info.androidRelease, isNotEmpty);
  });

  testWidgets('composeMail answers true or false, no crash', (tester) async {
    final opened = await AndroidFeedbackComposer().compose(
      to: 'feedback@example.com',
      subject: 'Subject',
      body: 'Body',
    );

    expect(opened, isA<bool>());
  });
}
