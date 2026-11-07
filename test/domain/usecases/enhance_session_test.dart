import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/lighting/enhancement_gate.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';

import '../../support/ocr_fakes.dart';

/// The light correction in the queue (ADR-030): the corrected picture is read
/// too and the version with more words is the page; the PDF picture and its
/// text come from the same version.
void main() {
  late FakeEnhancer enhancer;
  late FakeOcrEngine engine;
  late OcrTestRig rig;

  /// The engine says [originalWords] for the first picture of a page and
  /// [enhancedWords] for the picture the enhancer made.
  void script({required int originalWords, required int enhancedWords}) {
    engine.respond = (image) {
      final enhanced = enhancer.targets.contains(image.path);
      final words = enhanced ? enhancedWords : originalWords;
      return OcrSuccess(
        fakeResult([fakeLine(List.filled(words, 'w').join(' '))]),
      );
    };
  }

  setUp(() {
    enhancer = FakeEnhancer();
    engine = FakeOcrEngine();
    rig = OcrTestRig(engine: engine, enhancer: enhancer);
  });

  OcrSession start() => rig.recognize.start(packId: 'greek');

  test('nothing is corrected unless the user asked', () async {
    script(originalWords: 5, enhancedWords: 9);
    final session = start()
      ..add('p1', 'p1.jpg')
      ..close();

    final done = await session.finished;

    expect(enhancer.sources, isEmpty);
    expect(engine.recognized, hasLength(1));
    expect(done.pages.single.enhancement, isNull);
  });

  test(
    'asked before the reading: more words, the corrected one wins',
    () async {
      script(originalWords: 5, enhancedWords: 9);
      final session = start()..add('p1', 'p1.jpg');
      final used = session.requestEnhance('p1');
      session.close();

      final done = await session.finished;

      expect(await used, isTrue);
      final page = done.pages.single;
      expect(page.enhancement, EnhancementOutcome.applied);
      expect(countWords(page.outcome), 9);
      // The picture of the PDF is the corrected one, the text comes from it.
      expect(page.image!.path, enhancer.targets.single);
      // One working file per page: the first copy was deleted.
      expect(rig.workStore.files, {enhancer.targets.single});
      expect(engine.recognized, hasLength(2));
    },
  );

  test('the corrected picture loses words: the original is kept', () async {
    script(originalWords: 9, enhancedWords: 4);
    final session = start()..add('p1', 'p1.jpg');
    final used = session.requestEnhance('p1');
    session.close();

    final done = await session.finished;

    expect(await used, isFalse);
    final page = done.pages.single;
    expect(page.enhancement, EnhancementOutcome.keptOriginal);
    expect(countWords(page.outcome), 9);
    expect(page.image!.path, isNot(enhancer.targets.single));
    // The rejected picture does not stay in the cache.
    expect(rig.workStore.files, {page.image!.path});
    expect(rig.workStore.files, isNot(contains(enhancer.targets.single)));
  });

  test('a tie keeps the original', () async {
    script(originalWords: 6, enhancedWords: 6);
    final session = start()..add('p1', 'p1.jpg');
    final used = session.requestEnhance('p1');
    session.close();

    final done = await session.finished;

    expect(await used, isFalse);
    expect(done.pages.single.enhancement, EnhancementOutcome.keptOriginal);
  });

  test('a correction that cannot be made leaves the page as it was', () async {
    enhancer.succeed = false;
    script(originalWords: 6, enhancedWords: 0);
    final session = start()..add('p1', 'p1.jpg');
    final used = session.requestEnhance('p1');
    session.close();

    final done = await session.finished;

    expect(await used, isFalse);
    expect(done.pages.single.enhancement, EnhancementOutcome.failed);
    expect(countWords(done.pages.single.outcome), 6);
    expect(rig.workStore.files, hasLength(1));
  });

  test(
    'a page that is already read is read again only when corrected',
    () async {
      script(originalWords: 5, enhancedWords: 8);
      final session = start()
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg')
        ..close();
      final first = await session.finished;
      expect(engine.recognized, hasLength(2));
      final firstImage = first.pages.first.image!.path;

      final used = await session.requestEnhance('p1');

      expect(used, isTrue);
      // Only the corrected picture was read again, not the original.
      expect(engine.recognized, hasLength(3));
      final now = session.snapshot;
      expect(now.pages.first.enhancement, EnhancementOutcome.applied);
      expect(now.pages.first.image!.path, isNot(firstImage));
      expect(now.pages.last.enhancement, isNull);
      expect(now.allDone, isTrue);
    },
  );

  test('asking twice does nothing the second time', () async {
    script(originalWords: 5, enhancedWords: 8);
    final session = start()
      ..add('p1', 'p1.jpg')
      ..close();
    await session.finished;
    expect(await session.requestEnhance('p1'), isTrue);
    expect(await session.requestEnhance('p1'), isFalse);
    expect(enhancer.sources, hasLength(1));
  });

  test('a page whose working copy is gone is not corrected', () async {
    script(originalWords: 5, enhancedWords: 8);
    final session = start()
      ..add('p1', 'p1.jpg')
      ..close();
    await session.finished;
    await session.releaseWorkingCopies();

    expect(await session.requestEnhance('p1'), isFalse);
    expect(enhancer.sources, isEmpty);
  });

  test('without an enhancer on the platform nothing happens', () async {
    rig = OcrTestRig(engine: engine);
    final session = rig.recognize.start(packId: 'greek')
      ..add('p1', 'p1.jpg')
      ..close();
    await session.finished;

    expect(await session.requestEnhance('p1'), isFalse);
  });

  test('a cancel while the correction runs leaves no picture behind', () async {
    script(originalWords: 5, enhancedWords: 8);
    enhancer.gate = Completer<void>();
    final session = start()..add('p1', 'p1.jpg');
    final used = session.requestEnhance('p1');
    session.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await session.cancel();
    enhancer.gate!.complete();
    await used;
    await session.dispose();

    expect(rig.workStore.files, isEmpty);
  });
}
