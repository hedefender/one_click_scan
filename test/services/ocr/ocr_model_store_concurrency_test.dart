import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/services/ocr/ocr_model_store.dart';

void main() {
  late Directory dir;
  final registry = OcrLanguagePackRegistry.standard;
  final pack = registry.byId('greek')!;

  setUp(() => dir = Directory.systemTemp.createTempSync('model_store'));
  tearDown(() => dir.deleteSync(recursive: true));

  OcrModelStore store(List<String> loads) => OcrModelStore(
    directory: Directory('${dir.path}/models'),
    registry: registry,
    loadAsset: (path) async {
      loads.add(path);
      // Slow, so two callers overlap.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final name = path.split('/').last;
      final size = [
        registry.detector,
        pack.model,
        pack.dictionary,
      ].firstWhere((f) => f.name == name).bytes;
      return ByteData.sublistView(Uint8List(size));
    },
  );

  test(
    'preload and the first page asking at once both get the files',
    () async {
      final loads = <String>[];
      final s = store(loads);

      final results = await Future.wait([s.resolve(pack), s.resolve(pack)]);

      expect(results[0].detPath, results[1].detPath);
      for (final r in results) {
        expect(File(r.detPath).existsSync(), isTrue);
        expect(File(r.recPath).existsSync(), isTrue);
        expect(File(r.dictPath).existsSync(), isTrue);
      }
      // Each file was taken from the APK once, not twice.
      expect(loads.toSet().length, loads.length);
      expect(
        Directory('${dir.path}/models')
            .listSync()
            .where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );
    },
  );

  test('a failed call does not block the next one', () async {
    var fail = true;
    final s = OcrModelStore(
      directory: Directory('${dir.path}/models2'),
      registry: registry,
      loadAsset: (path) async {
        if (fail) throw StateError('missing');
        final name = path.split('/').last;
        final size = [
          registry.detector,
          pack.model,
          pack.dictionary,
        ].firstWhere((f) => f.name == name).bytes;
        return ByteData.sublistView(Uint8List(size));
      },
    );

    await expectLater(s.resolve(pack), throwsA(isA<OcrModelException>()));
    fail = false;

    expect((await s.resolve(pack)).packId, 'greek');
  });
}
