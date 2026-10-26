import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';

import '../../support/ocr_fakes.dart';

void main() {
  late OcrTestRig rig;

  setUp(() => rig = OcrTestRig());

  group('releaseWorkingCopies (the pictures are in the PDF)', () {
    test('deletes the files, keeps the results and the description of the '
        'image', () async {
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg')
        ..close();
      final done = await session.finished;
      expect(rig.workStore.files, hasLength(2));

      await session.releaseWorkingCopies();

      expect(rig.workStore.files, isEmpty);
      final after = session.snapshot;
      expect(after.pages.every((p) => p.outcome is OcrSuccess), isTrue);
      expect(after.pages.every((p) => p.workingCopyDeleted), isTrue);
      expect(after.pages.every((p) => p.hasWorkingFile), isFalse);
      // The check screen still shows the capture size.
      expect(after.pages.first.image, done.pages.first.image);
    });

    test('is idempotent and dispose does not delete a second time', () async {
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..close();
      await session.finished;

      await session.releaseWorkingCopies();
      await session.releaseWorkingCopies();
      await session.dispose();

      expect(rig.workStore.deleted, hasLength(1));
    });

    test('does not touch a page that is still being read', () async {
      rig.engine.gate = Completer<void>();
      final session = rig.recognize.start(packId: 'greek')..add('p1', 'p1.jpg');
      await pumpEventQueue();
      expect(rig.workStore.files, hasLength(1));

      await session.releaseWorkingCopies();

      expect(rig.workStore.files, hasLength(1));
      rig.engine.gate!.complete();
      session.close();
      await session.finished;
      await session.dispose();
    });
  });

  group('stopReading (make the PDF without waiting for the text)', () {
    test('the running page is cancelled, the next ones only get their '
        'picture', () async {
      rig.engine.gate = Completer<void>();
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg')
        ..add('p3', 'p3.jpg');
      await pumpEventQueue();
      expect(rig.engine.recognized, hasLength(1)); // page 1 is being read

      session.stopReading();
      session.close();
      final done = await session.finished;

      expect(
        done.pages.map((p) => p.outcome),
        everyElement(isA<OcrCancelled>()),
      );
      // Every page has its picture, so a PDF can be made.
      expect(done.pages.map((p) => p.image), everyElement(isNotNull));
      expect(rig.workStore.files, hasLength(3));
      // The engine was not asked to read the pages after the first.
      expect(rig.engine.recognized, hasLength(1));
      await session.dispose();
    });

    test('pages already read keep their result', () async {
      final session = rig.recognize.start(packId: 'greek')..add('p1', 'p1.jpg');
      await pumpEventQueue();
      rig.engine.gate = Completer<void>();
      session.add('p2', 'p2.jpg');
      await pumpEventQueue();

      session.stopReading();
      session.close();
      final done = await session.finished;

      expect(done.pages[0].outcome, isA<OcrSuccess>());
      expect(done.pages[1].outcome, isA<OcrCancelled>());
      await session.dispose();
    });

    test('after it a page added late is still prepared, not read', () async {
      final session = rig.recognize.start(packId: 'greek');
      session.stopReading();
      session
        ..add('p1', 'p1.jpg')
        ..close();

      final done = await session.finished;

      expect(done.pages.single.outcome, isA<OcrCancelled>());
      expect(done.pages.single.image, isNotNull);
      expect(rig.engine.recognized, isEmpty);
    });

    test('ignored after dispose', () async {
      final session = rig.recognize.start(packId: 'greek')..close();
      await session.dispose();

      session.stopReading(); // must not throw
    });
  });
}
