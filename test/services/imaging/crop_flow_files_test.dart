import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/domain/entities/page_crop_outcome.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/ports/page_cropper.dart';
import 'package:one_click_scan/domain/usecases/prepare_image_for_ocr.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/domain/usecases/straighten_page.dart';
import 'package:one_click_scan/services/image/dart_upright_image_maker.dart';
import 'package:one_click_scan/services/image/file_image_header_reader.dart';
import 'package:one_click_scan/services/image/io_ocr_work_store.dart';
import 'package:one_click_scan/services/imaging/isolate_page_cropper.dart';
import 'package:one_click_scan/services/pdf/dart_pdf_builder.dart';

import '../../support/fakes.dart' show RecordingLogger;
import '../../support/ocr_fakes.dart';
import '../../support/pdf_inspect.dart';
import '../../support/synth/scene.dart';
import 'crop_page_job_test.dart' show plainPage, spec;

/// The real files end to end on the PC: the shots of the camera, the working
/// copies, the crop in its isolate, and the PDF. Only the OCR engine is a fake.
void main() {
  late Directory dir;
  late Directory shots;
  late IoOcrWorkStore workStore;
  late OcrSession session;
  late FakeOcrEngine engine;
  late List<File> originals;
  late List<List<int>> originalBytes;

  /// Three photos: a tilted page, a page on a dark table, and an empty table
  /// (which must keep the whole frame).
  final specs = [
    spec('tilt', width: 1200, height: 1600, seed: 31, rollDeg: 9, tiltXDeg: 12),
    spec(
      'dark',
      width: 1200,
      height: 1600,
      seed: 32,
      background: Background.dark,
      rollDeg: -6,
    ),
    spec(
      'empty',
      width: 1200,
      height: 1600,
      seed: 33,
      hasDocument: false,
      background: Background.lines,
    ),
  ];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('crop_flow_files');
    shots = Directory('${dir.path}/shots')..createSync();
    workStore = IoOcrWorkStore(Directory('${dir.path}/ocr_work'));
    originals = [];
    for (var i = 0; i < specs.length; i++) {
      final r = renderScene(specs[i], plainPage());
      final image = r.image.clone();
      final file = File('${shots.path}/shot_${i + 1}.jpg')
        ..writeAsBytesSync(img.encodeJpg(image, quality: 92));
      originals.add(file);
    }
    originalBytes = [for (final f in originals) f.readAsBytesSync()];
    engine = FakeOcrEngine();
  });

  tearDown(() async {
    await session.dispose();
    dir.deleteSync(recursive: true);
  });

  OcrSession startSession(PageCropper cropper) {
    final prepare = PrepareImageForOcr(
      headerReader: const FileImageHeaderReader(),
      dartMaker: const DartUprightImageMaker(),
      nativeMaker: const DartUprightImageMaker(),
      workStore: workStore,
    );
    return session = RecognizePages(
      engine: engine,
      prepare: prepare,
      workStore: workStore,
      straighten: StraightenPage(cropper: cropper, workStore: workStore),
    ).start(packId: 'greek');
  }

  List<File> cacheFiles() => Directory('${dir.path}/ocr_work').existsSync()
      ? Directory('${dir.path}/ocr_work').listSync().whereType<File>().toList()
      : [];

  test('the photos of the camera are byte for byte the same afterwards, the '
      'crop is a new file, the empty table keeps its whole frame', () async {
    startSession(const IsolatePageCropper());
    for (final f in originals) {
      session.add(f.path, f.path);
    }
    session.close();

    final done = await session.finished;

    // Originals: untouched, byte for byte.
    for (var i = 0; i < originals.length; i++) {
      expect(originals[i].readAsBytesSync(), originalBytes[i]);
    }
    expect(done.pages[0].crop, isA<PageCropped>());
    expect(done.pages[1].crop, isA<PageCropped>());
    expect(done.pages[2].crop, isA<PageWholeFrame>());
    // One working file per page and nothing else in the cache.
    expect(cacheFiles(), hasLength(3));
    for (final p in done.pages) {
      expect(p.image!.path, startsWith('${dir.path}/ocr_work'));
      expect(File(p.image!.path).existsSync(), isTrue);
    }
    // The engine read exactly those pictures, in capture order.
    expect(engine.recognized, [for (final p in done.pages) p.image!.path]);
    // The size of the page in the file is the size the entity says.
    for (final p in done.pages) {
      final decoded = img.decodeJpg(File(p.image!.path).readAsBytesSync())!;
      expect(
        (decoded.width, decoded.height),
        (p.image!.width, p.image!.height),
      );
    }
  });

  test(
    'the PDF page has the proportions of the straightened picture',
    () async {
      startSession(const IsolatePageCropper());
      session.add(originals[0].path, originals[0].path);
      session.close();
      final done = await session.finished;
      final page = done.pages.single;
      expect(page.crop, isA<PageCropped>());

      final font = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
      final builder = DartPdfBuilder(
        workDirectory: Directory('${dir.path}/pdf_work'),
        loadFont: () async => font,
        logger: RecordingLogger(),
      );
      final pdf = await builder.build([
        PdfPageInput(image: page.image!, outcome: page.outcome!),
      ]);

      final box = PdfInspector(File(pdf.path).readAsBytesSync())
          .mediaBoxes
          .single;
      final ratio = box.$1 / box.$2;
      expect(ratio, closeTo(page.image!.width / page.image!.height, 0.002));
      // An upright A-series page, not the tilted whole frame (1200 x 1600).
      expect(ratio, closeTo(300 / 420, 0.05));
      expect(
        img.decodeJpg(File(page.image!.path).readAsBytesSync())!.width,
        isNot(1200),
      );
    },
  );

  test('a cancel in the middle leaves the cache empty and the photos '
      'untouched', () async {
    startSession(const IsolatePageCropper());
    for (final f in originals) {
      session.add(f.path, f.path);
    }
    session.close();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    await session.cancel();
    await session.finished;
    await session.dispose();
    // A killed crop may still be closing; give it a moment, then look.
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(cacheFiles(), isEmpty);
    for (var i = 0; i < originals.length; i++) {
      expect(originals[i].readAsBytesSync(), originalBytes[i]);
    }
  });

  test('undoing a shot that is being straightened leaves no file', () async {
    startSession(const IsolatePageCropper());
    session.add(originals[0].path, originals[0].path);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await session.remove(originals[0].path);
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(cacheFiles(), isEmpty);
    expect(originals[0].readAsBytesSync(), originalBytes[0]);
  });
}
