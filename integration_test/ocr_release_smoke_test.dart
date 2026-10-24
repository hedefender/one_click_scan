import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/ocr_smoke.dart';

/// The same smoke as the release APK of tool/run_ocr_release_smoke.sh, as an
/// ordinary integration test (debug build):
///   tool/run_integration_test.sh `<emulator-id>` integration_test/ocr_release_smoke_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('models load, a page is read, the native decode answers', (
    tester,
  ) async {
    final result = await runOcrSmoke();
    // ignore: avoid_print
    print('OCRIT smoke $result');
  });
}
