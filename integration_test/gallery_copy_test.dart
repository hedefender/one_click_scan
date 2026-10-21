import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/services/gallery/gal_gallery_service.dart';
import 'package:path_provider/path_provider.dart';

/// Saves one synthetic picture to the real Gallery (`gal`) under a chosen
/// name. Run on the Claude Code emulator only (the copy stays in its
/// `Pictures/`); then look at the MediaStore, see docs/PHASE_1_2_VALIDATION.md:
///   tool/run_integration_test.sh `<emulator-id>` integration_test/gallery_copy_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Gallery copy gets the name it was given', (tester) async {
    final cache = await getTemporaryDirectory();
    final source = File('${cache.path}/gallery_test_source.jpg');
    final picture = img.Image(width: 64, height: 48);
    img.fill(picture, color: img.ColorRgb8(30, 60, 120));
    await source.writeAsBytes(img.encodeJpg(picture));
    final work = Directory('${cache.path}/gallery_copies');

    await GalGalleryService(workDirectory: work)
        .saveImage(source.path, fileName: 'scan_2000-01-01_01.jpg');

    // The named temporary copy is gone again, the source is untouched.
    expect(work.existsSync() ? work.listSync() : <FileSystemEntity>[], isEmpty);
    expect(source.existsSync(), isTrue);
    await source.delete();
  });
}
