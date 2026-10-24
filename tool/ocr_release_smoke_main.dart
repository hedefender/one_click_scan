import 'package:flutter/widgets.dart';
import 'package:one_click_scan/services/scan_services_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../integration_test/support/ocr_smoke.dart';

/// Entry point for the release smoke (tool/run_ocr_release_smoke.sh): a
/// release APK (R8 on) that, on start-up, runs the OCR smoke and then touches
/// the other plugins the app uses (the camera, shared_preferences), and prints
/// one line, `OCRSMOKE ok ...` or `OCRSMOKE FAILED ...`, to logcat. The real
/// app is not involved; only the code under test is.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  try {
    final result = await runOcrSmoke();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('smoke', 'ok');
    final prefsOk = preferences.getString('smoke') == 'ok';
    await preferences.remove('smoke');

    final services = await createPlatformScanServices();
    final opened = await services.camera.open();
    await services.camera.close();

    // ignore: avoid_print
    print(
      'OCRSMOKE ok $result, preferences ${prefsOk ? 'ok' : 'FAILED'}, '
      'camera ${opened.name}',
    );
  } catch (error) {
    // ignore: avoid_print
    print('OCRSMOKE FAILED ${error.runtimeType}: $error');
  }
}
