import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/domain/entities/page_crop_outcome.dart';
import 'package:one_click_scan/domain/ocr/ocr_cancellation.dart';
import 'package:one_click_scan/services/imaging/isolate_page_cropper.dart';

import '../../support/synth/scene.dart';
import 'crop_page_job_test.dart' show plainPage, spec;

void main() {
  late Directory dir;
  late String source;
  const cropper = IsolatePageCropper();

  setUpAll(() {
    // One big photo for the whole file: the crop takes a measurable time.
    final r = renderScene(
      spec('big', width: 1800, height: 2400, rollDeg: 7, tiltXDeg: 10),
      plainPage(),
    );
    final d = Directory.systemTemp.createTempSync('isolate_cropper_src');
    source = '${d.path}/photo.jpg';
    File(source).writeAsBytesSync(img.encodeJpg(r.image, quality: 92));
    addTearDown(() => d.deleteSync(recursive: true));
  });

  setUp(() => dir = Directory.systemTemp.createTempSync('isolate_cropper'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<PageCropOutcome> run({
    String? from,
    Duration timeout = const Duration(seconds: 60),
    OcrCancellation? cancellation,
  }) => cropper.crop(
    source: from ?? source,
    target: '${dir.path}/out.jpg',
    maxSide: 2560,
    jpegQuality: 95,
    focalLength35mm: 26,
    timeout: timeout,
    cancellation: cancellation,
  );

  bool targetExists() => File('${dir.path}/out.jpg').existsSync();

  test('finds the page and writes the straightened JPEG', () async {
    final outcome = await run();

    expect(outcome, isA<PageCropped>());
    final cropped = outcome as PageCropped;
    expect(cropped.confidence, greaterThanOrEqualTo(0.5));
    final out = img.decodeJpg(File('${dir.path}/out.jpg').readAsBytesSync())!;
    expect((out.width, out.height), (cropped.width, cropped.height));
  });

  test('the work is not done in the isolate that called it', () async {
    // If the crop ran on the calling isolate, this timer could not fire for
    // as long as the crop takes.
    var maxGapMicros = 0;
    var last = Stopwatch()..start();
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      if (last.elapsedMicroseconds > maxGapMicros) {
        maxGapMicros = last.elapsedMicroseconds;
      }
      last = Stopwatch()..start();
    });
    final watch = Stopwatch()..start();
    final outcome = await run();
    watch.stop();
    timer.cancel();

    expect(outcome, isA<PageCropped>());
    expect(
      watch.elapsedMicroseconds,
      greaterThan(150000),
      reason: 'the photo is big enough for the check to mean something',
    );
    expect(maxGapMicros, lessThan(watch.elapsedMicroseconds ~/ 2));
  });

  test('a timeout is the whole frame, the isolate is gone and no file is '
      'left', () async {
    final outcome = await run(timeout: const Duration(milliseconds: 20));

    expect(outcome, isA<PageWholeFrame>());
    expect((outcome as PageWholeFrame).reason, WholeFrameReason.timedOut);
    // Wait longer than the crop needs: a late write would show up here.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(targetExists(), isFalse);
  });

  test('a cancel while it runs stops it at once and leaves no file', () async {
    final cancel = OcrCancellation();
    final pending = run(cancellation: cancel);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    cancel.cancel();

    final outcome = await pending;

    expect((outcome as PageWholeFrame).reason, WholeFrameReason.cancelled);
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(targetExists(), isFalse);
  });

  test('already cancelled: nothing is started', () async {
    final cancel = OcrCancellation()..cancel();

    final outcome = await run(cancellation: cancel);

    expect((outcome as PageWholeFrame).reason, WholeFrameReason.cancelled);
    expect(targetExists(), isFalse);
  });

  test('a file that is not an image is the whole frame', () async {
    final junk = File('${dir.path}/junk.jpg')
      ..writeAsBytesSync(Uint8List.fromList([9, 9, 9]));

    final outcome = await run(from: junk.path);

    expect((outcome as PageWholeFrame).reason, WholeFrameReason.failed);
    expect(targetExists(), isFalse);
  });

  test('a missing file is the whole frame, not an exception', () async {
    final outcome = await run(from: '${dir.path}/missing.jpg');

    expect((outcome as PageWholeFrame).reason, WholeFrameReason.failed);
  });

  test('many crops in a row leave no isolate or port behind', () async {
    for (var i = 0; i < 6; i++) {
      final outcome = await run(timeout: const Duration(milliseconds: 5));
      expect(outcome, isA<PageWholeFrame>());
    }
    final ok = await run();
    expect(ok, isA<PageCropped>());
  });
}
