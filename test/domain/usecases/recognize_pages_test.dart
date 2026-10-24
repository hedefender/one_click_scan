import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_line.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/ocr_progress.dart';
import 'package:one_click_scan/domain/ocr/ocr_config.dart';
import 'package:one_click_scan/domain/ports/image_header_reader.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';

import '../../support/ocr_fakes.dart';

void main() {
  late OcrTestRig rig;

  setUp(() => rig = OcrTestRig());

  OcrOutcome outcomeOf(OcrSessionSnapshot s, int page) =>
      s.pages[page].outcome!;

  group('one page', () {
    test('success: the result carries the engine lines', () async {
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..close();

      final done = await session.finished;

      final outcome = outcomeOf(done, 0);
      expect(outcome, isA<OcrSuccess>());
      expect((outcome as OcrSuccess).result.packId, 'greek');
      expect(done.isFinished, isTrue);
      expect(done.pages.single.status, OcrPageStatus.done);
    });

    test(
      'low confidence lines are flagged, nothing is removed or edited',
      () async {
        rig.engine.respond = (_) => OcrSuccess(
          fakeResult([
            fakeLine('Σύνολο 12,50', confidence: 0.98, row: 0),
            fakeLine('xq#~!', confidence: 0.11, row: 1),
          ]),
        );
        final session = rig.recognize.start(packId: 'greek')
          ..add('p1', 'p1.jpg')
          ..close();

        final result =
            (outcomeOf(await session.finished, 0) as OcrSuccess).result;

        expect(result.lines.map((l) => l.text), ['Σύνολο 12,50', 'xq#~!']);
        expect(result.lines.map((l) => l.filtered), [false, true]);
        expect(result.text, 'Σύνολο 12,50');
        expect(result.rawText, 'Σύνολο 12,50\nxq#~!');
      },
    );

    test('timeout is a value, not an exception', () async {
      rig.engine.respond = (_) => const OcrTimedOut(OcrConfig.pageTimeout);
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..close();

      expect(outcomeOf(await session.finished, 0), isA<OcrTimedOut>());
    });

    test('engine failure is passed on', () async {
      rig.engine.respond = (_) =>
          const OcrFailed(OcrFailureReason.modelUnavailable);
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..close();

      expect(
        outcomeOf(await session.finished, 0),
        const OcrFailed(OcrFailureReason.modelUnavailable),
      );
    });

    test('an engine that throws still gives a failed outcome', () async {
      rig.engine.respond = (_) => throw StateError('boom');
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..close();

      expect(
        outcomeOf(await session.finished, 0),
        const OcrFailed(OcrFailureReason.engineError),
      );
    });

    test('an image that cannot be prepared never reaches the engine', () async {
      rig.header.fallback = null;
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..close();

      expect(
        outcomeOf(await session.finished, 0),
        const OcrFailed(OcrFailureReason.imageUnreadable),
      );
      expect(rig.engine.recognized, isEmpty);
    });

    test(
      'a 200 MP photo fails as too large, the next page still works',
      () async {
        rig.header.headers['huge.jpg'] = const ImageHeader(
          width: 12240,
          height: 16320,
          orientation: 1,
        );
        final session = rig.recognize.start(packId: 'greek')
          ..add('huge', 'huge.jpg')
          ..add('ok', 'ok.jpg')
          ..close();

        final done = await session.finished;

        expect(
          outcomeOf(done, 0),
          const OcrFailed(OcrFailureReason.imageTooLarge),
        );
        expect(outcomeOf(done, 1), isA<OcrSuccess>());
      },
    );
  });

  group('progress', () {
    test(
      'the page reports the engine progress as text-ready numbers',
      () async {
        rig.engine.progress = const [
          OcrProgress(OcrStage.detecting),
          OcrProgress(OcrStage.recognizing, done: 12, total: 51),
        ];
        final gate = rig.engine.gate = Completer<void>();
        final session = rig.recognize.start(packId: 'greek')
          ..add('p1', 'p1.jpg');

        await pumpEventQueue();

        final page = session.snapshot.pages.single;
        expect(page.status, OcrPageStatus.recognizing);
        expect(
          page.progress,
          const OcrProgress(OcrStage.recognizing, done: 12, total: 51),
        );

        gate.complete();
        session.close();
        await session.finished;
      },
    );

    test('snapshots are broadcast to the screen', () async {
      final seen = <OcrSessionSnapshot>[];
      final session = rig.recognize.start(packId: 'greek');
      final sub = session.snapshots.listen(seen.add);

      session
        ..add('p1', 'p1.jpg')
        ..close();
      await session.finished;
      await pumpEventQueue();
      await sub.cancel();

      expect(seen, isNotEmpty);
      expect(seen.last.isFinished, isTrue);
      expect(
        seen.map((s) => s.pages.isEmpty ? null : s.pages.first.status),
        contains(OcrPageStatus.preparing),
      );
    });
  });

  group('pipelining of several pages', () {
    test('results come back in capture order, one page at a time', () async {
      // The first page is slow; the second and third are added meanwhile.
      final gate = rig.engine.gate = Completer<void>();
      final session = rig.recognize.start(packId: 'greek')..add('p1', 'p1.jpg');
      await pumpEventQueue();
      session
        ..add('p2', 'p2.jpg')
        ..add('p3', 'p3.jpg');
      await pumpEventQueue();

      // p1 is being read, p2 and p3 wait their turn.
      expect(session.snapshot.pages.map((p) => p.status), [
        OcrPageStatus.recognizing,
        OcrPageStatus.queued,
        OcrPageStatus.queued,
      ]);

      gate.complete();
      session.close();
      final done = await session.finished;

      expect(done.pages.map((p) => p.key), ['p1', 'p2', 'p3']);
      expect(rig.engine.recognized.length, 3);
      expect(rig.engine.maxRunning, 1);
      expect(done.pages.every((p) => p.outcome is OcrSuccess), isTrue);
    });

    test(
      'reading starts as soon as the page is added, before the scan ends',
      () async {
        final session = rig.recognize.start(packId: 'greek')
          ..add('p1', 'p1.jpg');
        await pumpEventQueue();

        expect(rig.engine.recognized, hasLength(1));
        expect(session.snapshot.closed, isFalse);
        expect(session.snapshot.allDone, isTrue);
        expect(session.snapshot.isFinished, isFalse);

        session.close();
        expect((await session.finished).isFinished, isTrue);
      },
    );

    test('a deleted queued page is never read', () async {
      final gate = rig.engine.gate = Completer<void>();
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg');
      await pumpEventQueue();

      await session.remove('p2');
      gate.complete();
      session.close();
      final done = await session.finished;

      expect(done.pages.map((p) => p.key), ['p1']);
      expect(rig.engine.recognized, hasLength(1));
    });

    test(
      'deleting the page being read cancels it and frees its file',
      () async {
        final gate = rig.engine.gate = Completer<void>();
        final session = rig.recognize.start(packId: 'greek')
          ..add('p1', 'p1.jpg');
        await pumpEventQueue();
        expect(rig.workStore.files, hasLength(1));

        await session.remove('p1');
        await pumpEventQueue();

        expect(session.snapshot.pages, isEmpty);
        expect(rig.workStore.files, isEmpty);
        gate.complete();
      },
    );
  });

  group('cancel', () {
    test('cancel stops the running page and marks the queued ones', () async {
      rig.engine.gate = Completer<void>();
      final session = rig.recognize.start(packId: 'greek')
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg');
      await pumpEventQueue();

      await session.cancel();
      final done = await session.finished;

      expect(
        done.pages.map((p) => p.outcome),
        everyElement(isA<OcrCancelled>()),
      );
      expect(rig.engine.recognized, hasLength(1));
    });

    test('a pack of pages added after cancel is ignored', () async {
      final session = rig.recognize.start(packId: 'greek');
      await session.cancel();

      session.add('late', 'late.jpg');

      expect(session.snapshot.pages, isEmpty);
    });

    test('a second scan after a cancelled one works', () async {
      rig.engine.gate = Completer<void>();
      final first = rig.recognize.start(packId: 'greek')..add('p1', 'p1.jpg');
      await pumpEventQueue();
      await first.cancel();
      await first.dispose();

      rig.engine.gate = null;
      final second = rig.recognize.start(packId: 'greek')
        ..add('q1', 'q1.jpg')
        ..close();

      expect(outcomeOf(await second.finished, 0), isA<OcrSuccess>());
    });
  });

  group('cleanup', () {
    test(
      'dispose deletes the working copies and releases the engine',
      () async {
        final session = rig.recognize.start(packId: 'greek')
          ..add('p1', 'p1.jpg')
          ..add('p2', 'p2.jpg')
          ..close();
        await session.finished;
        expect(rig.workStore.files, hasLength(2));

        await session.dispose();

        expect(rig.workStore.files, isEmpty);
        expect(rig.engine.releaseCalls, 1);
      },
    );

    test('preload goes to the engine with the chosen pack', () async {
      await rig.recognize.preload('latin');

      expect(rig.engine.preloaded, ['latin']);
    });
  });

  test('an empty page is a success with no lines', () async {
    rig.engine.respond = (_) => OcrSuccess(fakeResult(const <OcrLine>[]));
    final session = rig.recognize.start(packId: 'greek')
      ..add('p1', 'p1.jpg')
      ..close();

    final result = (outcomeOf(await session.finished, 0) as OcrSuccess).result;

    expect(result.lines, isEmpty);
    expect(result.text, '');
  });

  test('closing a session with no pages finishes at once', () async {
    final session = rig.recognize.start(packId: 'greek')..close();

    expect((await session.finished).pages, isEmpty);
  });
}
