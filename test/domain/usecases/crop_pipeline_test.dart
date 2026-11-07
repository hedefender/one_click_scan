import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/page_crop_outcome.dart';
import 'package:one_click_scan/domain/imaging/page_crop_config.dart';
import 'package:one_click_scan/domain/imaging/quad.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';

import '../../support/ocr_fakes.dart';

/// The queue with the crop step (ADR-029): prepare and crop run one page ahead
/// of the reading, in capture order, with a bounded number of waiting pages.
void main() {
  late FakeCropper cropper;
  late OcrTestRig rig;

  setUp(() {
    cropper = FakeCropper();
    rig = OcrTestRig(cropper: cropper);
  });

  OcrSession start() => rig.recognize.start(packId: 'greek');

  List<OcrPageStatus> statuses(OcrSession s) =>
      s.snapshot.pages.map((p) => p.status).toList();

  group('the picture that is read is the straightened one', () {
    test('the engine reads the crop, the page keeps it for the PDF', () async {
      final session = start()
        ..add('p1', 'p1.jpg')
        ..close();

      final done = await session.finished;

      final page = done.pages.single;
      expect(page.crop, isA<PageCropped>());
      expect(page.image!.width, 1200);
      expect(page.image!.height, 1700);
      // The engine got the file the crop wrote, not the first working copy.
      expect(rig.engine.recognized, [page.image!.path]);
      // One working file per page: the uncropped copy was deleted.
      expect(rig.workStore.files, {page.image!.path});
      expect(done.croppedCount, 1);
    });

    test('a page without a crop step is read as before', () async {
      rig = OcrTestRig();
      final session = start()
        ..add('p1', 'p1.jpg')
        ..close();

      final done = await session.finished;

      expect(done.pages.single.crop, isNull);
      expect(done.pages.single.outcome, isA<OcrSuccess>());
      expect(done.croppedCount, 0);
    });

    test(
      'the counters say how many pages kept the whole frame, and why',
      () async {
        final outcomes = <PageCropOutcome>[
          PageCropped(
            quad: Quad.frame(10, 10),
            confidence: 0.9,
            width: 800,
            height: 1000,
          ),
          const PageWholeFrame(WholeFrameReason.lowConfidence),
          const PageWholeFrame(WholeFrameReason.lowConfidence),
          const PageWholeFrame(WholeFrameReason.timedOut),
        ];
        var n = 0;
        cropper.respond = (_) => outcomes[n++];
        final session = start();
        for (var i = 1; i <= 4; i++) {
          session.add('p$i', 'p$i.jpg');
        }
        session.close();

        final done = await session.finished;

        expect(done.croppedCount, 1);
        expect(done.wholeFrameReasons, {
          WholeFrameReason.lowConfidence: 2,
          WholeFrameReason.timedOut: 1,
        });
      },
    );
  });

  group('pipelining', () {
    test('the next page is prepared while one is being read, at most '
        '${PageCropConfig.prepareAhead} wait for the engine', () async {
      final gate = rig.engine.gate = Completer<void>();
      final session = start();
      for (var i = 1; i <= 5; i++) {
        session.add('p$i', 'p$i.jpg');
      }
      await pumpEventQueue();

      // p1 is read; p2 and p3 are prepared and wait; p4 and p5 are not touched.
      expect(statuses(session), [
        OcrPageStatus.recognizing,
        OcrPageStatus.ready,
        OcrPageStatus.ready,
        OcrPageStatus.queued,
        OcrPageStatus.queued,
      ]);
      expect(cropper.calls, hasLength(3));
      expect(rig.workStore.files, hasLength(3));

      gate.complete();
      session.close();
      final done = await session.finished;

      expect(done.pages.map((p) => p.key), ['p1', 'p2', 'p3', 'p4', 'p5']);
      expect(done.pages.every((p) => p.outcome is OcrSuccess), isTrue);
      expect(cropper.calls, hasLength(5));
      // Never two crops, never two readings at once.
      expect(cropper.maxRunning, 1);
      expect(rig.engine.maxRunning, 1);
    });

    test('the preparation runs ahead of the reading, not after it', () async {
      final gate = rig.engine.gate = Completer<void>();
      final session = start()
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg');
      await pumpEventQueue();

      // The engine is still on p1 and the crop of p2 has already run.
      expect(statuses(session).first, OcrPageStatus.recognizing);
      expect(cropper.calls, hasLength(2));
      expect(rig.engine.recognized, hasLength(1));

      gate.complete();
      session.close();
      await session.finished;
    });

    test(
      'a slow crop holds only the pages behind it, the order stays',
      () async {
        final gate = cropper.gate = Completer<void>();
        final session = start();
        for (var i = 1; i <= 3; i++) {
          session.add('p$i', 'p$i.jpg');
        }
        await pumpEventQueue();

        expect(statuses(session), [
          OcrPageStatus.preparing,
          OcrPageStatus.queued,
          OcrPageStatus.queued,
        ]);
        expect(rig.engine.recognized, isEmpty);

        cropper.gate = null;
        gate.complete();
        session.close();
        final done = await session.finished;

        expect(done.pages.map((p) => p.key), ['p1', 'p2', 'p3']);
        expect(rig.engine.recognized, hasLength(3));
      },
    );

    test('shots added while the engine works are picked up after it', () async {
      final session = start()..add('p1', 'p1.jpg');
      await pumpEventQueue();
      session
        ..add('p2', 'p2.jpg')
        ..close();

      final done = await session.finished;

      expect(done.pages.map((p) => p.key), ['p1', 'p2']);
      expect(done.pages.every((p) => p.status == OcrPageStatus.done), isTrue);
    });
  });

  group('every failure of the crop is the whole frame', () {
    test('an exception in the cropper: the page is read, the picture is the '
        'first working copy', () async {
      cropper.throwWith = StateError('boom');
      final session = start()
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg')
        ..close();

      final done = await session.finished;

      for (final page in done.pages) {
        expect(page.crop, const PageWholeFrame(WholeFrameReason.failed));
        expect(page.outcome, isA<OcrSuccess>());
        expect(page.image, isNotNull);
        expect(page.image!.width, 1500); // the working copy, not a crop
      }
      expect(rig.workStore.files, hasLength(2)); // no stray target
    });

    test('a timeout of the crop does not stop the scan', () async {
      cropper.outcome = const PageWholeFrame(WholeFrameReason.timedOut);
      final session = start()
        ..add('p1', 'p1.jpg')
        ..close();

      final done = await session.finished;

      expect(done.pages.single.outcome, isA<OcrSuccess>());
      expect(rig.workStore.files, hasLength(1));
    });
  });

  group('undo of the last shot while the page is processed', () {
    test('the crop is stopped and every file of the page is gone', () async {
      cropper.gate = Completer<void>();
      final session = start()..add('p1', 'p1.jpg');
      await pumpEventQueue();
      expect(statuses(session), [OcrPageStatus.preparing]);

      await session.remove('p1');
      await pumpEventQueue();

      expect(cropper.calls.single.cancellation!.isCancelled, isTrue);
      expect(session.snapshot.pages, isEmpty);
      expect(rig.workStore.files, isEmpty);
      expect(rig.engine.recognized, isEmpty);
    });

    test('a page that finished its crop but was undone is not kept', () async {
      rig.engine.gate = Completer<void>();
      final session = start()
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg');
      await pumpEventQueue();
      expect(statuses(session), [
        OcrPageStatus.recognizing,
        OcrPageStatus.ready,
      ]);

      await session.remove('p2');
      await session.remove('p1');
      await pumpEventQueue();

      expect(session.snapshot.pages, isEmpty);
      expect(rig.workStore.files, isEmpty);
    });

    test('the pages after the undone one go on', () async {
      final gate = cropper.gate = Completer<void>();
      final session = start()
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg');
      await pumpEventQueue();

      cropper.gate = null;
      await session.remove('p1');
      gate.complete();
      session.close();
      final done = await session.finished;

      expect(done.pages.map((p) => p.key), ['p2']);
      expect(done.pages.single.outcome, isA<OcrSuccess>());
      await session.dispose();
      expect(rig.workStore.files, isEmpty);
    });
  });

  group('cancel after "Done" (ADR-028)', () {
    test('a crop that runs is stopped and the waiting pages are cancelled, '
        'nothing is left after dispose', () async {
      cropper.gate = Completer<void>();
      final session = start()
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg')
        ..add('p3', 'p3.jpg')
        ..close();
      await pumpEventQueue();

      await session.cancel();
      final done = await session.finished;
      await session.dispose();

      expect(done.pages.every((p) => p.outcome is OcrCancelled), isTrue);
      expect(cropper.calls.first.cancellation!.isCancelled, isTrue);
      expect(rig.engine.recognized, isEmpty);
      expect(rig.workStore.files, isEmpty);
    });

    test('pages that wait for the engine are cancelled and cleaned', () async {
      rig.engine.gate = Completer<void>();
      final session = start();
      for (var i = 1; i <= 3; i++) {
        session.add('p$i', 'p$i.jpg');
      }
      session.close();
      await pumpEventQueue();
      expect(rig.workStore.files, hasLength(3));

      await session.cancel();
      final done = await session.finished;
      await session.dispose();

      expect(done.pages.every((p) => p.outcome is OcrCancelled), isTrue);
      expect(rig.workStore.files, isEmpty);
    });

    test('dispose while a crop runs leaves no file when it ends', () async {
      final gate = cropper.gate = Completer<void>();
      final session = start()..add('p1', 'p1.jpg');
      await pumpEventQueue();

      await session.dispose();
      gate.complete();
      await pumpEventQueue();

      expect(rig.workStore.files, isEmpty);
    });
  });

  group('"make the PDF without waiting for the text"', () {
    test('a crop that runs is let to finish, the page goes in cropped and '
        'without text', () async {
      final gate = cropper.gate = Completer<void>();
      final session = start()
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg')
        ..close();
      await pumpEventQueue();

      cropper.gate = null;
      session.stopReading();
      gate.complete();
      final done = await session.finished;

      expect(rig.engine.recognized, isEmpty);
      for (final page in done.pages) {
        expect(page.outcome, isA<OcrCancelled>());
        expect(page.crop, isA<PageCropped>());
        expect(page.image, isNotNull);
        expect(page.hasWorkingFile, isTrue);
      }
    });
  });

  group('the working copies', () {
    test('releasing them after the PDF deletes the cropped files', () async {
      final session = start()
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg')
        ..close();
      await session.finished;
      expect(rig.workStore.files, hasLength(2));

      await session.releaseWorkingCopies();

      expect(rig.workStore.files, isEmpty);
      expect(session.snapshot.pages.every((p) => p.workingCopyDeleted), isTrue);
    });

    test('the originals are never given to the crop or the store', () async {
      final session = start()
        ..add('shot_1.jpg', 'shots/shot_1.jpg')
        ..close();
      await session.finished;

      // The crop reads the working copy, never the file of the camera.
      expect(cropper.calls.single.source, startsWith('work/'));
      expect(rig.workStore.deleted.every((p) => p.startsWith('work/')), isTrue);
    });
  });
}
