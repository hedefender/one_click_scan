import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/stored_scan.dart';
import 'package:one_click_scan/domain/ports/image_header_reader.dart';
import 'package:one_click_scan/domain/ports/open_pdf.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/scan/scan_naming.dart';
import 'package:one_click_scan/domain/usecases/load_settings.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/domain/usecases/store_scan_pdf.dart';
import 'package:one_click_scan/features/scan/scan_result_cubit.dart';
import 'package:one_click_scan/features/scan/scan_result_state.dart';

import '../../support/fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/pdf_fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
  late OcrTestRig rig;
  late PdfTestRig pdf;
  late FakeScanFileStore store;
  late RecordingLogger logger;
  late InMemoryKeyValueStore keyValues;
  late LoadSettings loadSettings;
  late ScanResultCubit cubit;
  late OcrSession session;

  const scan = StoredScan(
    stem: '2026-10-21_19-05-12',
    pictures: [
      StoredPicture(
        fileName: '2026-10-21_19-05-12_1.jpg',
        sourcePath: 'cache/1.jpg',
      ),
    ],
  );

  Future<void> setUpRig({bool withFolder = true, int pages = 1}) async {
    rig = OcrTestRig();
    pdf = PdfTestRig();
    store = FakeScanFileStore();
    logger = RecordingLogger();
    keyValues = InMemoryKeyValueStore();
    final container = await buildTestContainer(
      store: keyValues,
      scanFileStore: store,
      logger: logger,
      pdf: pdf.services,
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: withFolder ? testFolder : null,
      ),
    );
    loadSettings = container<LoadSettings>();
    session = rig.recognize.start(packId: 'greek');
    for (var i = 1; i <= pages; i++) {
      session.add('shot$i', 'cache/$i.jpg');
    }
  }

  ScanResultCubit makeCubit([OcrSession? override]) => ScanResultCubit(
    scan: scan,
    session: override ?? session,
    loadSettings: loadSettings,
    storePdf: StoreScanPdf(
      builder: pdf.builder,
      fileStore: store,
      naming: ScanNaming(() => DateTime(2026, 10, 21, 19, 5, 12)),
      logger: logger,
    ),
    openPdf: pdf.opener,
    logger: logger,
  );

  tearDown(() async {
    await cubit.close();
    await session.dispose();
  });

  group('the PDF of a scan', () {
    test('waits for the reading, then creates and stores the PDF', () async {
      await setUpRig();
      rig.engine.gate = Completer<void>();
      cubit = makeCubit();
      final states = <ScanPdfPhase>[];
      cubit.stream.listen((s) => states.add(s.phase));

      final started = cubit.start();
      await pumpEventQueue();
      expect(cubit.state.phase, ScanPdfPhase.readingText);
      expect(cubit.state.busy, isTrue);
      expect(pdf.builder.builds, isEmpty);

      session.close();
      rig.engine.gate!.complete();
      await started;

      expect(cubit.state.phase, ScanPdfPhase.saved);
      expect(cubit.state.busy, isFalse);
      await pumpEventQueue();
      expect(states, contains(ScanPdfPhase.creating));
      expect(states.last, ScanPdfPhase.saved);
      expect(cubit.state.pdf!.fileName, '2026-10-21_19-05-12.pdf');
      expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
    });

    test(
      'the pages go in capture order, with their picture and outcome',
      () async {
        await setUpRig(pages: 3);
        cubit = makeCubit();
        session.close();

        await cubit.start();

        final built = pdf.builder.builds.single;
        expect(built.map((p) => p.image.path), [
          'work/upright_1.jpg',
          'work/upright_2.jpg',
          'work/upright_3.jpg',
        ]);
        expect(built.every((p) => p.outcome is OcrSuccess), isTrue);
        expect(cubit.state.pdf!.pageCount, 3);
      },
    );

    test('the folder is the one in the settings', () async {
      await setUpRig();
      cubit = makeCubit();
      session.close();

      await cubit.start();

      expect(store.copies.single.$1, 'pdf');
    });

    test('progress: "page k of n" while the reading goes on', () async {
      await setUpRig(pages: 3);
      rig.engine.gate = Completer<void>();
      cubit = makeCubit();

      unawaited(cubit.start());
      await pumpEventQueue();

      expect(cubit.state.pagesTotal, 3);
      expect(cubit.state.pagesRead, 0);
      expect(cubit.state.pageInProgress, 1);

      rig.engine.gate!.complete();
      await pumpEventQueue();
      session.close();
      await pumpEventQueue();
    });

    test('after a success the working copies are deleted', () async {
      await setUpRig(pages: 2);
      cubit = makeCubit();
      session.close();
      expect(rig.workStore.files, isEmpty); // nothing prepared yet

      await cubit.start();

      expect(cubit.state.phase, ScanPdfPhase.saved);
      expect(rig.workStore.files, isEmpty);
      expect(rig.workStore.deleted, hasLength(2));
      // The OCR check screen still has its results.
      expect(
        session.snapshot.pages.every((p) => p.outcome is OcrSuccess),
        isTrue,
      );
    });

    test('the cache PDF is deleted after storing', () async {
      await setUpRig();
      cubit = makeCubit();
      session.close();

      await cubit.start();

      expect(pdf.builder.discarded, hasLength(1));
    });
  });

  group('pages without text still go in', () {
    test(
      'a timed out, failed and cancelled page: PDF made, pages counted',
      () async {
        await setUpRig(pages: 4);
        var n = 0;
        rig.engine.respond = (_) {
          n++;
          return switch (n) {
            1 => OcrSuccess(fakeResult([fakeLine('Total 12,50')])),
            2 => const OcrTimedOut(Duration(seconds: 45)),
            3 => const OcrFailed(OcrFailureReason.engineError),
            _ => const OcrCancelled(),
          };
        };
        cubit = makeCubit();
        session.close();

        await cubit.start();

        expect(cubit.state.phase, ScanPdfPhase.saved);
        expect(cubit.state.pdf!.pageCount, 4);
        expect(cubit.state.pdf!.textPageCount, 1);
        expect(cubit.state.pdf!.pagesWithoutText, 3);
      },
    );

    test(
      'a page whose lines were all filtered counts as without text',
      () async {
        await setUpRig();
        rig.engine.respond = (_) =>
            OcrSuccess(fakeResult([fakeLine('scribble', confidence: 0.3)]));
        cubit = makeCubit();
        session.close();

        await cubit.start();

        expect(cubit.state.pdf!.textPageCount, 0);
      },
    );

    test(
      '"without waiting for the text": cancelled pages, PDF still made',
      () async {
        await setUpRig(pages: 3);
        rig.engine.gate = Completer<void>();
        cubit = makeCubit();
        final started = cubit.start();
        await pumpEventQueue();
        expect(cubit.state.phase, ScanPdfPhase.readingText);

        await cubit.skipText();
        session.close();
        await started;

        expect(cubit.state.phase, ScanPdfPhase.saved);
        expect(cubit.state.pdf!.pageCount, 3);
        expect(cubit.state.pdf!.textPageCount, 0);
      },
    );

    test('skipText does nothing once the PDF is being made', () async {
      await setUpRig();
      cubit = makeCubit();
      session.close();
      await cubit.start();

      await cubit.skipText();

      expect(cubit.state.phase, ScanPdfPhase.saved);
    });

    test('a second scan after a cancelled one works normally', () async {
      await setUpRig();
      rig.engine.gate = Completer<void>();
      cubit = makeCubit();
      final first = cubit.start();
      await pumpEventQueue();
      await cubit.skipText();
      session.close();
      await first;
      expect(cubit.state.pdf!.textPageCount, 0);
      await cubit.close();
      await session.dispose();

      // A fresh scan with the same collaborators.
      rig.engine.gate = null;
      session = rig.recognize.start(packId: 'greek')
        ..add('shot1', 'cache/9.jpg')
        ..close();
      cubit = makeCubit();
      await cubit.start();

      expect(cubit.state.phase, ScanPdfPhase.saved);
      expect(cubit.state.pdf!.textPageCount, 1);
      expect(store.files('pdf'), hasLength(2));
    });
  });

  group('failures: the photos stay, nothing crashes', () {
    test(
      'the writer fails: failed state, working copies kept for a retry',
      () async {
        await setUpRig();
        pdf.builder.failWith = const ScanPdfException(
          ScanPdfFailure.buildFailed,
        );
        cubit = makeCubit();
        session.close();

        await cubit.start();

        expect(cubit.state.phase, ScanPdfPhase.failed);
        expect(cubit.state.failure, ScanPdfFailure.buildFailed);
        expect(cubit.state.busy, isFalse);
        expect(rig.workStore.files, isNotEmpty);
        expect(store.files('pictures'), isEmpty); // not touched
      },
    );

    test('writing into the folder fails: writeFailed', () async {
      await setUpRig();
      store.failSubfolder = 'pdf';
      cubit = makeCubit();
      session.close();

      await cubit.start();

      expect(cubit.state.phase, ScanPdfPhase.failed);
      expect(cubit.state.failure, ScanPdfFailure.writeFailed);
    });

    test('no access to the folder: noAccess', () async {
      await setUpRig();
      store.failEverything = ScanStoreFailure.noAccess;
      cubit = makeCubit();
      session.close();

      await cubit.start();

      expect(cubit.state.failure, ScanPdfFailure.noAccess);
    });

    test('no folder in the settings: noAccess', () async {
      await setUpRig(withFolder: false);
      cubit = makeCubit();
      session.close();

      await cubit.start();

      expect(cubit.state.failure, ScanPdfFailure.noAccess);
      expect(pdf.builder.builds, isEmpty);
    });

    test('a photo that could not be prepared: pageImageMissing', () async {
      await setUpRig();
      await session.dispose();
      rig.header.headers['cache/big.jpg'] = const ImageHeader(
        width: 25000,
        height: 20000,
        orientation: 1,
      );
      session = rig.recognize.start(packId: 'greek')
        ..add('shot1', 'cache/big.jpg')
        ..close();
      cubit = makeCubit();

      await cubit.start();

      expect(cubit.state.phase, ScanPdfPhase.failed);
      expect(cubit.state.failure, ScanPdfFailure.pageImageMissing);
      expect(pdf.builder.builds, isEmpty);
    });

    test('no reading session at all: failed, not a crash', () async {
      await setUpRig();
      cubit = ScanResultCubit(
        scan: scan,
        session: null,
        loadSettings: loadSettings,
        storePdf: StoreScanPdf(
          builder: pdf.builder,
          fileStore: store,
          naming: ScanNaming(DateTime.now),
          logger: logger,
        ),
        openPdf: pdf.opener,
        logger: logger,
      );

      await cubit.start();

      expect(cubit.state.phase, ScanPdfPhase.failed);
      expect(cubit.state.failure, ScanPdfFailure.pageImageMissing);
    });

    test('an unexpected error is caught and logged without content', () async {
      await setUpRig();
      pdf.builder.failWith = null;
      cubit = makeCubit();
      session.close();
      store.failEverything = ScanStoreFailure.unknown;

      await cubit.start();

      expect(cubit.state.phase, ScanPdfPhase.failed);
      expect(logger.messages.join(), isNot(contains('2026-10-21')));
    });

    test(
      'retry after a failure makes the PDF and then deletes the pictures',
      () async {
        await setUpRig();
        store.failSubfolder = 'pdf';
        cubit = makeCubit();
        session.close();
        await cubit.start();
        expect(cubit.state.phase, ScanPdfPhase.failed);
        expect(rig.workStore.files, isNotEmpty);

        store.failSubfolder = null;
        await cubit.retry();

        expect(cubit.state.phase, ScanPdfPhase.saved);
        expect(cubit.state.failure, isNull);
        expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
        expect(rig.workStore.files, isEmpty);
      },
    );

    test('retry does nothing unless the last attempt failed', () async {
      await setUpRig();
      cubit = makeCubit();
      session.close();
      await cubit.start();

      await cubit.retry();

      expect(pdf.builder.builds, hasLength(1));
    });

    test('a failed retry stays failed, with the new reason', () async {
      await setUpRig();
      store.failSubfolder = 'pdf';
      cubit = makeCubit();
      session.close();
      await cubit.start();

      store.failSubfolder = null;
      store.failEverything = ScanStoreFailure.noAccess;
      await cubit.retry();

      expect(cubit.state.phase, ScanPdfPhase.failed);
      expect(cubit.state.failure, ScanPdfFailure.noAccess);
    });
  });

  group('open', () {
    test('hands the URI of the stored PDF to the viewer', () async {
      await setUpRig();
      cubit = makeCubit();
      session.close();
      await cubit.start();

      await cubit.openPdf();

      expect(pdf.opener.opened, [cubit.state.pdf!.uri]);
      expect(cubit.state.openProblem, isNull);
    });

    test('no viewer installed: a message state', () async {
      await setUpRig();
      pdf.opener.result = OpenPdfResult.noViewer;
      cubit = makeCubit();
      session.close();
      await cubit.start();

      await cubit.openPdf();

      expect(cubit.state.openProblem, OpenPdfResult.noViewer);
      expect(cubit.state.phase, ScanPdfPhase.saved);
    });

    test('a later success clears the message', () async {
      await setUpRig();
      pdf.opener.result = OpenPdfResult.failed;
      cubit = makeCubit();
      session.close();
      await cubit.start();
      await cubit.openPdf();
      expect(cubit.state.openProblem, OpenPdfResult.failed);

      pdf.opener.result = OpenPdfResult.opened;
      await cubit.openPdf();

      expect(cubit.state.openProblem, isNull);
    });

    test('nothing to open before the PDF exists', () async {
      await setUpRig();
      rig.engine.gate = Completer<void>();
      cubit = makeCubit();
      unawaited(cubit.start());
      await pumpEventQueue();

      await cubit.openPdf();

      expect(pdf.opener.opened, isEmpty);
      rig.engine.gate!.complete();
      session.close();
      await pumpEventQueue();
    });
  });

  test('closing the cubit while it waits does not crash', () async {
    await setUpRig();
    rig.engine.gate = Completer<void>();
    cubit = makeCubit();
    unawaited(cubit.start());
    await pumpEventQueue();

    await cubit.close();
    rig.engine.gate!.complete();
    session.close();
    await pumpEventQueue();

    expect(pdf.builder.builds, isEmpty);
  });
}
