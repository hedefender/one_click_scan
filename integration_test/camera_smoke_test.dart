import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';
import 'package:one_click_scan/services/camera/plugin_camera_service.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/fakes.dart';
import '../test/support/scan_fakes.dart';

/// Optional smoke test of the REAL camera plugin, meant for the Claude Code
/// emulator whose back camera is the `virtualscene` (never the host webcam).
///
/// The permission dialog cannot be driven by integration_test, so grant it
/// first, on the Claude Code emulator only, and again after EVERY install or
/// uninstall (the grant is lost with them):
///   adb -s `<claude-code-emulator>` shell pm grant com.example.one_click_scan android.permission.CAMERA
///   flutter test integration_test/camera_smoke_test.dart -d `<claude-code-emulator>`
///
/// If the grant is missing the dialog appears and nobody presses it: the
/// tests fail after [_permissionWait] with a message that says so, instead of
/// hanging.
const _permissionWait = Duration(seconds: 20);

const _grantHint =
    'The CAMERA permission dialog is probably waiting on the emulator screen. '
    'Grant the permission with adb (never by hand) and run the test again: '
    'adb -s <claude-code-emulator> shell pm grant '
    'com.example.one_click_scan android.permission.CAMERA';

/// Opens and closes the real camera once, with a time limit, so a missing
/// permission fails fast and clearly.
Future<void> requireCameraPermission(Directory pages) async {
  final camera = PluginCameraService(cacheDirectory: pages);
  try {
    final result = await camera.open().timeout(_permissionWait);
    expect(
      result,
      CameraOpenResult.ready,
      reason: 'The camera did not open ($result). $_grantHint',
    );
  } on TimeoutException {
    fail(_grantHint);
  } finally {
    await camera.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real camera: opens, shoots a JPEG into the cache', (
    tester,
  ) async {
    final cache = await getTemporaryDirectory();
    final pages = Directory('${cache.path}/smoke_pages');
    await requireCameraPermission(pages);
    final camera = PluginCameraService(cacheDirectory: pages);

    final opened = await camera.open();
    expect(opened, CameraOpenResult.ready, reason: _grantHint);

    final page = await camera.capture(order: 1);
    final file = File(page.path);
    expect(file.existsSync(), isTrue);
    final bytes = file.readAsBytesSync();
    expect(bytes.length, greaterThan(1000));
    expect(bytes[0], 0xFF);
    expect(bytes[1], 0xD8);

    final info = JpegInfo.parse(bytes);
    // Printed for the orientation report (see docs/PHASE_1_VALIDATION.md).
    debugPrint(
      'SMOKE jpeg ${info.width}x${info.height} '
      'exifOrientation=${info.exifOrientation}',
    );

    await camera.close();
    await pages.delete(recursive: true);
  });

  testWidgets('real camera inside the app: single page ends on the result', (
    tester,
  ) async {
    final cache = await getTemporaryDirectory();
    final pages = Directory('${cache.path}/smoke_app_pages');
    await requireCameraPermission(pages);
    final store = FakeScanFileStore();
    final container = await buildTestContainer(
      camera: PluginCameraService(cacheDirectory: pages),
      scanFileStore: store,
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
      ),
    );

    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    // The preview keeps rendering, so pumpAndSettle may never settle here.
    await tester.pump(const Duration(seconds: 3));

    expect(find.byKey(ScanKeys.preview), findsOneWidget);
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Scan saved'), findsOneWidget);
    expect(store.files('pictures'), ['2026-10-21_19-05-12_1.jpg']);
  });
}

/// Minimal JPEG header reader: size and EXIF orientation (1 = upright).
class JpegInfo {
  JpegInfo(this.width, this.height, this.exifOrientation);

  final int width;
  final int height;

  /// `null` when there is no EXIF orientation tag.
  final int? exifOrientation;

  factory JpegInfo.parse(Uint8List bytes) {
    var width = 0;
    var height = 0;
    int? orientation;
    var i = 2;
    while (i + 4 < bytes.length && bytes[i] == 0xFF) {
      final marker = bytes[i + 1];
      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      final body = i + 4;
      if (marker == 0xE1 && _isExif(bytes, body)) {
        orientation = _readOrientation(bytes, body + 6);
      }
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof) {
        height = (bytes[body + 1] << 8) | bytes[body + 2];
        width = (bytes[body + 3] << 8) | bytes[body + 4];
        break;
      }
      i += 2 + length;
    }
    return JpegInfo(width, height, orientation);
  }

  static bool _isExif(Uint8List b, int at) =>
      b[at] == 0x45 && b[at + 1] == 0x78 && b[at + 2] == 0x69;

  static int? _readOrientation(Uint8List b, int tiff) {
    final little = b[tiff] == 0x49;
    int u16(int at) =>
        little ? b[at] | (b[at + 1] << 8) : (b[at] << 8) | b[at + 1];
    int u32(int at) => little
        ? b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)
        : (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
    final ifd = tiff + u32(tiff + 4);
    final count = u16(ifd);
    for (var n = 0; n < count; n++) {
      final entry = ifd + 2 + n * 12;
      if (u16(entry) == 0x0112) return u16(entry + 8);
    }
    return null;
  }
}
