import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/services/gallery/media_store_gallery_service.dart';
import 'package:path_provider/path_provider.dart';

/// Saves one synthetic picture to the real Gallery (MediaStore) under a chosen
/// name, gets its URI, and deletes it again by that URI. Run on the Claude Code
/// emulator only:
///   tool/run_integration_test.sh `<emulator-id>` integration_test/gallery_copy_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Gallery copy has a URI and is deleted by it', (
    tester,
  ) async {
    final cache = await getTemporaryDirectory();
    final source = File('${cache.path}/gallery_test_source.jpg');
    final picture = img.Image(width: 64, height: 48);
    img.fill(picture, color: img.ColorRgb8(30, 60, 120));
    await source.writeAsBytes(img.encodeJpg(picture));
    final gallery = MediaStoreGalleryService();

    final uri = await gallery.saveImage(
      source.path,
      fileName: 'scan_2000-01-01_01.jpg',
    );
    expect(uri, startsWith('content://media/'));
    expect(source.existsSync(), isTrue);

    await gallery.deleteImage(uri);
    // Deleting again is not an error: the entry is already gone.
    await gallery.deleteImage(uri);
    await source.delete();
  });
}
