import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/ocr_result.dart';
import 'package:one_click_scan/domain/ocr/ocr_cancellation.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/domain/usecases/prepare_image_for_ocr.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:path_provider/path_provider.dart';

import 'support/synthetic_pages.dart';

/// OCR with the real models on the Claude Code emulator (invented pages only):
///   tool/run_integration_test.sh `<emulator-id>` integration_test/ocr_engine_test.dart
///
/// Times and the peak memory are printed as `OCRIT ...` lines for the report;
/// they are not asserted (an x86 emulator says nothing about the phone).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late OcrServices ocr;
  late PrepareImageForOcr prepare;
  late RecognizePages recognize;
  late Directory work;
  late img.Image greekPage;
  late img.Image latinPage;

  void report(String message) {
    // ignore: avoid_print
    print('OCRIT $message');
  }

  String peakMb() => (ProcessInfo.maxRss / (1024 * 1024)).toStringAsFixed(0);

  /// Reads one file through the same session the scan uses.
  Future<OcrOutcome> readFile(
    String path,
    String packId, {
    OcrSession? session,
  }) async {
    final s = session ?? recognize.start(packId: packId);
    s.add(path, path);
    s.close();
    final done = await s.finished;
    return done.pages.single.outcome!;
  }

  OcrResult success(OcrOutcome outcome) {
    expect(outcome, isA<OcrSuccess>(), reason: 'outcome: $outcome');
    return (outcome as OcrSuccess).result;
  }

  setUpAll(() async {
    final registry = OcrLanguagePackRegistry.standard;
    ocr = await createPlatformOcrServices(
      registry: registry,
      logger: const DebugAppLogger(),
    );
    prepare = PrepareImageForOcr(
      headerReader: ocr.headerReader,
      dartMaker: ocr.dartMaker,
      nativeMaker: ocr.nativeMaker,
      workStore: ocr.workStore,
    );
    recognize = RecognizePages(
      engine: ocr.engine,
      prepare: prepare,
      workStore: ocr.workStore,
    );
    final cache = await getTemporaryDirectory();
    work = Directory('${cache.path}/ocr_it')..createSync(recursive: true);
    greekPage = await renderDocument(greekReceipt.lines);
    latinPage = await renderDocument(latinAccents.lines);
  });

  tearDownAll(() async {
    await ocr.engine.dispose();
    await ocr.workStore.purgeAll();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  testWidgets('greek pack reads Greek + English, coordinates in 0..1', (
    tester,
  ) async {
    final file = writeJpeg('${work.path}/greek.jpg', greekPage);
    final sw = Stopwatch()..start();
    final result = success(await readFile(file.path, OcrPackIds.greek));
    final recall = keyRecall(result.text, greekReceipt.keyTokens);
    report(
      'greek cold ${sw.elapsedMilliseconds} ms (engine ${result.duration.inMilliseconds} ms), '
      'boxes ${result.boxCount}, recall ${(recall * 100).toStringAsFixed(1)}%, '
      'image ${result.imageWidth}x${result.imageHeight}, peak RSS ${peakMb()} MB',
    );
    expect(recall, greaterThanOrEqualTo(0.95));
    expect(result.packId, OcrPackIds.greek);
    for (final line in result.lines) {
      expect(line.quad, hasLength(4));
      for (final p in line.quad) {
        expect(p.x, inInclusiveRange(0.0, 1.0));
        expect(p.y, inInclusiveRange(0.0, 1.0));
      }
      expect(line.confidence, inInclusiveRange(0.0, 1.0));
    }
    // Reading order: rows never go back up the page.
    final rowTops = <int, double>{};
    for (final line in result.lines) {
      rowTops.putIfAbsent(line.row, () => line.quad[0].y);
    }
    final ordered = rowTops.keys.toList()..sort();
    for (var i = 1; i < ordered.length; i++) {
      expect(
        rowTops[ordered[i]]!,
        greaterThanOrEqualTo(rowTops[ordered[i - 1]]! - 0.02),
      );
    }
  });

  testWidgets('latin pack keeps the accents', (tester) async {
    final file = writeJpeg('${work.path}/latin.jpg', latinPage);
    final result = success(await readFile(file.path, OcrPackIds.latin));
    final recall = keyRecall(result.text, latinAccents.keyTokens);
    report(
      'latin ${result.duration.inMilliseconds} ms, boxes ${result.boxCount}, '
      'recall ${(recall * 100).toStringAsFixed(1)}%, peak RSS ${peakMb()} MB',
    );
    expect(recall, greaterThanOrEqualTo(0.95));
  });

  testWidgets('the UI isolate keeps answering while a page is read', (
    tester,
  ) async {
    final file = writeJpeg('${work.path}/ui.jpg', greekPage);
    var ticks = 0;
    var maxGapMs = 0;
    var last = DateTime.now();
    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final now = DateTime.now();
      maxGapMs = math.max(maxGapMs, now.difference(last).inMilliseconds);
      last = now;
      ticks++;
    });
    final sw = Stopwatch()..start();
    success(await readFile(file.path, OcrPackIds.greek));
    timer.cancel();
    report(
      'UI timer: $ticks ticks in ${sw.elapsedMilliseconds} ms, '
      'longest gap $maxGapMs ms',
    );
    expect(ticks, greaterThan(10));
    expect(maxGapMs, lessThan(2000));
  });

  testWidgets('EXIF orientation 1..8 and the invalid 0 give the same text', (
    tester,
  ) async {
    final upright = success(
      await readFile(
        writeJpeg('${work.path}/o_ref.jpg', greekPage).path,
        OcrPackIds.greek,
      ),
    );
    for (final orientation in [0, 3, 6, 8]) {
      final stored = storedFor(greekPage, orientation == 0 ? 1 : orientation);
      final file = writeJpeg(
        '${work.path}/o_$orientation.jpg',
        stored,
        exifOrientation: orientation,
      );
      final result = success(await readFile(file.path, OcrPackIds.greek));
      final recall = keyRecall(result.text, greekReceipt.keyTokens);
      report(
        'orientation $orientation: ${result.imageWidth}x${result.imageHeight}, '
        'recall ${(recall * 100).toStringAsFixed(1)}%',
      );
      expect(result.imageWidth, upright.imageWidth);
      expect(result.imageHeight, upright.imageHeight);
      expect(recall, greaterThanOrEqualTo(0.95));
    }
  });

  testWidgets('the native and the Dart maker agree for EXIF 0..9', (
    tester,
  ) async {
    // Four coloured quadrants: any wrong rotation or flip shows.
    final pattern = img.Image(width: 300, height: 200);
    final colours = [
      img.ColorRgb8(255, 0, 0),
      img.ColorRgb8(0, 200, 0),
      img.ColorRgb8(0, 0, 255),
      img.ColorRgb8(255, 255, 0),
    ];
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 300; x++) {
        pattern.setPixel(x, y, colours[(x < 150 ? 0 : 1) + (y < 100 ? 0 : 2)]);
      }
    }
    bool near(img.Pixel p, img.Color c) =>
        (p.r - c.r).abs() < 70 &&
        (p.g - c.g).abs() < 70 &&
        (p.b - c.b).abs() < 70;

    for (final tag in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]) {
      final valid = tag >= 1 && tag <= 8;
      final stored = storedFor(pattern, valid ? tag : 1);
      final file = writeJpeg(
        '${work.path}/parity_$tag.jpg',
        stored,
        exifOrientation: tag,
        quality: 95,
      );
      final results = <String, img.Image>{};
      for (final entry in {
        'dart': ocr.dartMaker,
        'native': ocr.nativeMaker,
      }.entries) {
        final target = '${work.path}/parity_${tag}_${entry.key}.jpg';
        final pixels = await entry.value.make(
          source: file.path,
          target: target,
          maxSide: 2560,
          jpegQuality: 95,
        );
        expect(
          (pixels.width, pixels.height),
          (300, 200),
          reason: '${entry.key} tag $tag',
        );
        results[entry.key] = img.decodeJpg(File(target).readAsBytesSync())!;
      }
      for (final entry in results.entries) {
        expect(
          near(entry.value.getPixel(40, 30), colours[0]),
          isTrue,
          reason: '${entry.key} tag $tag top-left',
        );
        expect(
          near(entry.value.getPixel(260, 30), colours[1]),
          isTrue,
          reason: '${entry.key} tag $tag top-right',
        );
        expect(
          near(entry.value.getPixel(40, 170), colours[2]),
          isTrue,
          reason: '${entry.key} tag $tag bottom-left',
        );
        expect(
          near(entry.value.getPixel(260, 170), colours[3]),
          isTrue,
          reason: '${entry.key} tag $tag bottom-right',
        );
      }
    }
    report('native and Dart makers agree for EXIF tags 0..9');
  });

  testWidgets('a rotated 12 MP photo (EXIF 6) is read upright natively', (
    tester,
  ) async {
    final big = img.Image(width: 4000, height: 3000, numChannels: 3);
    img.fill(big, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(big, img.copyResize(greekPage, width: 3000), dstX: 500);
    final file = writeJpeg(
      '${work.path}/big_rot.jpg',
      storedFor(big, 6),
      exifOrientation: 6,
      quality: 85,
    );
    final upright = await prepare(file.path);
    expect(upright.sourceWidth, 3000); // stored sideways
    expect(upright.sourceHeight, 4000);
    expect((upright.width, upright.height), (2560, 1920));
    final result = success(await readFile(file.path, OcrPackIds.greek));
    final recall = keyRecall(result.text, greekReceipt.keyTokens);
    report('12 MP EXIF 6: recall ${(recall * 100).toStringAsFixed(1)}%');
    expect(recall, greaterThanOrEqualTo(0.9));
    await ocr.workStore.delete(upright.path);
  });

  testWidgets('confidence of clean, degraded and scribbled lines', (
    tester,
  ) async {
    // For the threshold: how confident is the engine on text it reads well,
    // on blurred and low contrast text, and on strokes that are not text?
    final blurred = img.gaussianBlur(greekPage.clone(), radius: 3);
    final faint = greekPage.clone();
    for (final p in faint) {
      p
        ..r = 255 - ((255 - p.r) * 0.35).round()
        ..g = 255 - ((255 - p.g) * 0.35).round()
        ..b = 255 - ((255 - p.b) * 0.35).round();
    }
    final scribble = await renderScribbles();
    final stats = <String, List<double>>{};
    for (final entry in {
      'clean': greekPage,
      'blurred': blurred,
      'faint': faint,
      'scribble': scribble,
    }.entries) {
      final file = writeJpeg('${work.path}/conf_${entry.key}.jpg', entry.value);
      final result = success(await readFile(file.path, OcrPackIds.greek));
      stats[entry.key] = [for (final l in result.lines) l.confidence];
      final c = stats[entry.key]!..sort();
      String f(double v) => v.toStringAsFixed(2);
      report(
        'confidence ${entry.key}: ${c.length} lines'
        '${c.isEmpty ? '' : ', min ${f(c.first)}, median ${f(c[c.length ~/ 2])}, max ${f(c.last)}'}'
        '; below 0.5: ${c.where((v) => v < 0.5).length}',
      );
    }
    final clean = stats['clean']!;
    expect(clean, isNotEmpty);
    expect(clean.where((v) => v < 0.5), isEmpty);
  });

  testWidgets('a 12 MP photo goes through the native decode', (tester) async {
    // Same page pasted on a big white canvas: 4000 x 3000 = 12 MP.
    final big = img.Image(width: 4000, height: 3000, numChannels: 3);
    img.fill(big, color: img.ColorRgb8(255, 255, 255));
    final scaled = img.copyResize(greekPage, width: 3000);
    img.compositeImage(big, scaled, dstX: 500, dstY: 0);
    final file = writeJpeg(
      '${work.path}/big.jpg',
      big,
      exifOrientation: 1,
      quality: 85,
    );
    final upright = await prepare(file.path);
    expect(upright.sourceWidth, 4000);
    expect(upright.sourceHeight, 3000);
    expect(math.max(upright.width, upright.height), 2560);
    final result = success(await readFile(file.path, OcrPackIds.greek));
    final recall = keyRecall(result.text, greekReceipt.keyTokens);
    report(
      '12 MP: working ${upright.width}x${upright.height}, '
      'recall ${(recall * 100).toStringAsFixed(1)}%, peak RSS ${peakMb()} MB',
    );
    expect(recall, greaterThanOrEqualTo(0.9));
    await ocr.workStore.delete(upright.path);
  });

  testWidgets('headers above 400 MP are refused, a broken 200 MP file fails '
      'as unreadable, neither crashes', (tester) async {
    final tooBig = writeFakeHugeJpeg(
      '${work.path}/huge500.jpg',
      width: 25000,
      height: 20000,
    );
    expect(
      await readFile(tooBig.path, OcrPackIds.greek),
      const OcrFailed(OcrFailureReason.imageTooLarge),
    );
    // 200 MP in the header but no image data: the native decode is tried
    // (sampled) and fails in a controlled way.
    final broken = writeFakeHugeJpeg(
      '${work.path}/broken200.jpg',
      width: 12240,
      height: 16320,
    );
    expect(
      await readFile(broken.path, OcrPackIds.greek),
      const OcrFailed(OcrFailureReason.imageUnreadable),
    );
    // The engine is still fine afterwards.
    final ok = await readFile(
      writeJpeg('${work.path}/after_huge.jpg', latinPage).path,
      OcrPackIds.latin,
    );
    expect(ok, isA<OcrSuccess>());
  });

  testWidgets('a real 54 MP photo is read through the sampled native decode', (
    tester,
  ) async {
    // Made in a background isolate (about 300 MB of pixels there, not in the
    // test isolate). 8200 x 6600 = 54.1 MP, above the 50 MP full-decode limit.
    final path = '${work.path}/real54.jpg';
    final pageBytes = img.encodeJpg(greekPage, quality: 92);
    await makeBigPhotoInIsolate(path, pageBytes);
    final upright = await prepare(path);
    expect(upright.sourceMegapixels, greaterThan(50));
    expect(math.max(upright.width, upright.height), 2560);
    await ocr.workStore.delete(upright.path);

    final sw = Stopwatch()..start();
    final result = success(await readFile(path, OcrPackIds.greek));
    final recall = keyRecall(result.text, greekReceipt.keyTokens);
    report(
      '54 MP: ${sw.elapsedMilliseconds} ms in total, '
      'recall ${(recall * 100).toStringAsFixed(1)}%, peak RSS ${peakMb()} MB',
    );
    expect(recall, greaterThanOrEqualTo(0.9));
  });

  testWidgets('cancel in the middle, then the next call works', (tester) async {
    final file = writeJpeg('${work.path}/cancel.jpg', greekPage);
    final upright = await prepare(file.path);
    final cancellation = OcrCancellation();
    final pending = ocr.engine.recognize(
      upright,
      packId: OcrPackIds.greek,
      cancellation: cancellation,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    cancellation.cancel();
    expect(await pending, isA<OcrCancelled>());

    final again = await ocr.engine.recognize(upright, packId: OcrPackIds.greek);
    expect(again, isA<OcrSuccess>());
    await ocr.workStore.delete(upright.path);
  });

  testWidgets('timeout (tiny limit for the test) then the next call works', (
    tester,
  ) async {
    final file = writeJpeg('${work.path}/timeout.jpg', greekPage);
    final upright = await prepare(file.path);
    final timedOut = await ocr.engine.recognize(
      upright,
      packId: OcrPackIds.greek,
      timeout: const Duration(milliseconds: 5),
    );
    expect(timedOut, isA<OcrTimedOut>());

    final again = await ocr.engine.recognize(upright, packId: OcrPackIds.greek);
    expect(again, isA<OcrSuccess>());
    await ocr.workStore.delete(upright.path);
  });

  testWidgets('a damaged model file is refused, removed and extracted again', (
    tester,
  ) async {
    // Run once so the files exist, then change one byte of the recogniser
    // (same size: only the SHA-256 can tell).
    final file = writeJpeg('${work.path}/damaged.jpg', latinPage);
    success(await readFile(file.path, OcrPackIds.latin));
    final support = await getApplicationSupportDirectory();
    final model = File('${support.path}/ocr_models/rec_latin.onnx');
    expect(model.existsSync(), isTrue);
    final bytes = model.readAsBytesSync();
    bytes[bytes.length ~/ 2] ^= 0xFF;
    model.writeAsBytesSync(bytes);
    // The loaded session is in the worker already; release it so the next
    // page loads from the (damaged) file.
    await ocr.engine.release();

    final damaged = await readFile(file.path, OcrPackIds.latin);
    expect(damaged, const OcrFailed(OcrFailureReason.modelUnavailable));
    expect(model.existsSync(), isFalse, reason: 'the bad file is removed');

    final again = await readFile(file.path, OcrPackIds.latin);
    expect(again, isA<OcrSuccess>(), reason: 'extracted again from the APK');
    report('damaged model: refused once, then extracted again and read');
  });

  testWidgets('a Multi Page scan reads the pages in order', (tester) async {
    final a = writeJpeg('${work.path}/multi_a.jpg', greekPage);
    final b = writeJpeg('${work.path}/multi_b.jpg', latinPage);
    final session = recognize.start(packId: OcrPackIds.greek);
    final sw = Stopwatch()..start();
    session
      ..add('a', a.path)
      ..add('b', b.path)
      ..close();
    final done = await session.finished;
    report('multi page: 2 pages in ${sw.elapsedMilliseconds} ms');
    expect(done.pages.map((p) => p.key), ['a', 'b']);
    expect(done.pages.every((p) => p.outcome is OcrSuccess), isTrue);
    await session.dispose();
  });
}

/// Top level so the isolate closure captures nothing but two plain values.
void makeBigPhoto(String path, Uint8List pageBytes) {
  final page = img.decodeJpg(pageBytes)!;
  final big = img.Image(width: 8200, height: 6600, numChannels: 3);
  img.fill(big, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(big, img.copyResize(page, width: 8000), dstX: 100);
  File(path).writeAsBytesSync(img.encodeJpg(big, quality: 80));
}

/// Top level on purpose: a closure made inside a test would drag the whole
/// test context (with the engine's ports) into the isolate message.
Future<void> makeBigPhotoInIsolate(String path, Uint8List pageBytes) =>
    Isolate.run(() => makeBigPhoto(path, pageBytes));
