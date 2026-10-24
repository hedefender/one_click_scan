import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/services/ocr/model_verification.dart';
import 'package:one_click_scan/services/ocr/ocr_model_store.dart';

OcrModelFile describe(String name, List<int> bytes) => OcrModelFile(
  name: name,
  sha256: sha256.convert(bytes).toString(),
  bytes: bytes.length,
);

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ocr_models_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('verifyModelFile (SHA-256)', () {
    final content = utf8.encode('pretend this is a model');
    final expected = describe('m.onnx', content);

    test('the right file is ok', () async {
      final f = File('${dir.path}/m.onnx')..writeAsBytesSync(content);

      expect(await verifyModelFile(f.path, expected), ModelFileStatus.ok);
    });

    test('a missing file is reported as missing', () async {
      expect(
        await verifyModelFile('${dir.path}/none.onnx', expected),
        ModelFileStatus.missing,
      );
    });

    test('a file of the wrong size is reported before hashing', () async {
      final f = File('${dir.path}/m.onnx')..writeAsBytesSync([...content, 1]);

      expect(
        await verifyModelFile(f.path, expected),
        ModelFileStatus.wrongSize,
      );
    });

    test('a same-size file with other content has the wrong hash', () async {
      final tampered = [...content]..[0] ^= 0xFF;
      final f = File('${dir.path}/m.onnx')..writeAsBytesSync(tampered);

      expect(
        await verifyModelFile(f.path, expected),
        ModelFileStatus.wrongHash,
      );
    });
  });

  group('OcrModelStore (bundled assets to files)', () {
    final detBytes = List<int>.generate(50, (i) => i);
    final recBytes = List<int>.generate(70, (i) => i + 1);
    final dictBytes = utf8.encode('a\nb\n');
    final registry = OcrLanguagePackRegistry(
      detector: describe('det.onnx', detBytes),
      packs: [
        OcrLanguagePack(
          id: 'p',
          languageCodes: const ['en'],
          model: describe('rec_p.onnx', recBytes),
          dictionary: describe('dict_p.txt', dictBytes),
        ),
      ],
    );
    late Map<String, List<int>> assets;
    late List<String> loads;
    late OcrModelStore store;

    setUp(() {
      assets = {
        'assets/ocr/models/det.onnx': detBytes,
        'assets/ocr/models/rec_p.onnx': recBytes,
        'assets/ocr/models/dict_p.txt': dictBytes,
      };
      loads = [];
      store = OcrModelStore(
        directory: Directory('${dir.path}/models'),
        registry: registry,
        loadAsset: (path) async {
          loads.add(path);
          final bytes = assets[path];
          if (bytes == null) throw StateError('no asset');
          return ByteData.sublistView(Uint8List.fromList(bytes));
        },
      );
    });

    test('extracts the three files and returns their paths', () async {
      final paths = await store.resolve(registry.packs.single);

      expect(File(paths.detPath).readAsBytesSync(), detBytes);
      expect(File(paths.recPath).readAsBytesSync(), recBytes);
      expect(File(paths.dictPath).readAsBytesSync(), dictBytes);
      expect(paths.packId, 'p');
      expect(loads, hasLength(3));
    });

    test(
      'a second resolve reuses the files (nothing is extracted again)',
      () async {
        await store.resolve(registry.packs.single);
        loads.clear();

        await store.resolve(registry.packs.single);

        expect(loads, isEmpty);
      },
    );

    test('a truncated file on disk is extracted again', () async {
      final paths = await store.resolve(registry.packs.single);
      File(paths.recPath).writeAsBytesSync([1, 2, 3]);
      loads.clear();

      await store.resolve(registry.packs.single);

      expect(loads, ['assets/ocr/models/rec_p.onnx']);
      expect(File(paths.recPath).readAsBytesSync(), recBytes);
    });

    test('forget removes a file that failed its hash', () async {
      final paths = await store.resolve(registry.packs.single);

      await store.forget(registry.packs.single.model);

      expect(File(paths.recPath).existsSync(), isFalse);
      expect(File(paths.detPath).existsSync(), isTrue);
    });

    test(
      'a missing asset is an OcrModelException with the file name',
      () async {
        assets.remove('assets/ocr/models/rec_p.onnx');

        await expectLater(
          store.resolve(registry.packs.single),
          throwsA(
            isA<OcrModelException>().having(
              (e) => e.fileName,
              'fileName',
              'rec_p.onnx',
            ),
          ),
        );
      },
    );

    test('no half written file is left under the final name', () async {
      await store.resolve(registry.packs.single);

      final names = Directory('${dir.path}/models')
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
    });

    test(
      'paths survive the trip to the worker isolate as a plain map',
      () async {
        final paths = await store.resolve(registry.packs.single);

        final copy = OcrModelPaths.fromMap(paths.toMap());

        expect(copy.recPath, paths.recPath);
        expect(copy.rec, paths.rec);
        expect(copy.dict.sha256, paths.dict.sha256);
      },
    );
  });
}
