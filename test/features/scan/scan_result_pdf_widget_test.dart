import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/ports/open_pdf.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/ocr/ocr_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';

import '../../support/fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/pdf_fakes.dart';
import '../../support/scan_fakes.dart';

/// Scan -> result screen with the state of the PDF, real cubits, fake engine,
/// fake PDF writer and viewer.
void main() {
  late OcrTestRig rig;
  late PdfTestRig pdf;
  late FakeScanFileStore store;

  Future<void> pumpHome(WidgetTester tester, {String language = 'en'}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    rig = OcrTestRig();
    pdf = PdfTestRig();
    store = FakeScanFileStore();
    final values = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      config: AppConfig.forDeviceLanguage(language),
      store: values,
      scanFileStore: store,
      ocr: rig.services,
      pdf: pdf.services,
    );
    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: 'sender@example.com',
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: await build()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('single page: the PDF is saved, with its name, size and a button '
      'that opens it', (tester) async {
    await pumpHome(tester);

    await tapKey(tester, ScanKeys.capture);

    expect(find.text('PDF saved: 2026-10-21_19-05-12.pdf'), findsOneWidget);
    expect(find.text('1 page, 121 KB'), findsOneWidget);
    expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
    expect(find.byKey(ScanKeys.pdfOpen), findsOneWidget);
    expect(find.text('Open PDF'), findsOneWidget);
    // The OCR check button stays.
    expect(find.byKey(ScanKeys.resultOcr), findsOneWidget);
    // No promise of exact copying, only the warning to check.
    expect(find.byKey(ScanKeys.pdfNote), findsOneWidget);
    expect(find.textContaining('mistakes'), findsOneWidget);
    expect(find.byKey(ScanKeys.pdfNoText), findsNothing);
  });

  testWidgets('Open PDF hands the stored file to the viewer', (tester) async {
    await pumpHome(tester);
    await tapKey(tester, ScanKeys.capture);

    await tapKey(tester, ScanKeys.pdfOpen);

    expect(pdf.opener.opened, hasLength(1));
    expect(pdf.opener.opened.single, contains('2026-10-21_19-05-12.pdf'));
    expect(find.byKey(ScanKeys.pdfOpenProblem), findsNothing);
  });

  testWidgets('no app can open PDFs: a clear message, the PDF stays saved', (
    tester,
  ) async {
    await pumpHome(tester);
    pdf.opener.result = OpenPdfResult.noViewer;
    await tapKey(tester, ScanKeys.capture);

    await tapKey(tester, ScanKeys.pdfOpen);

    expect(
      find.text('No app on this phone can open PDF files.'),
      findsOneWidget,
    );
    expect(find.byKey(ScanKeys.pdfStatus), findsOneWidget);
  });

  testWidgets('three pages: one PDF, the name of the first page, 3 pages', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);

    await tapKey(tester, ScanKeys.done);

    expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
    expect(store.files('pictures'), hasLength(3));
    expect(find.text('3 pages, 121 KB'), findsOneWidget);
    expect(pdf.builder.builds.single, hasLength(3));
  });

  testWidgets('a page that timed out is flagged: its picture is in the PDF, '
      'without text', (tester) async {
    await pumpHome(tester);
    rig.engine.respond = (_) => const OcrTimedOut(Duration(seconds: 45));

    await tapKey(tester, ScanKeys.capture);

    expect(find.byKey(ScanKeys.pdfStatus), findsOneWidget);
    expect(
      find.text('1 page has no searchable text. Its picture is in the PDF.'),
      findsOneWidget,
    );
    expect(find.byKey(ScanKeys.pdfOpen), findsOneWidget);
  });

  testWidgets('two of three pages without text: the count is in the message', (
    tester,
  ) async {
    await pumpHome(tester);
    var n = 0;
    rig.engine.respond = (_) => ++n == 1
        ? OcrSuccess(fakeResult([fakeLine('ok')]))
        : const OcrFailed(OcrFailureReason.engineError);
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);

    await tapKey(tester, ScanKeys.done);

    expect(
      find.text(
        '2 pages have no searchable text. Their pictures are in the PDF.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('while the text is read: text progress, no spinner, no way '
      'back; the button makes the PDF without waiting', (tester) async {
    await pumpHome(tester);
    rig.engine.gate = Completer<void>();
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.done);

    expect(find.text('Reading page 1 of 2…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(ScanKeys.pdfOpen), findsNothing);
    // The back button of the page is off, with the reason as its label.
    final back = tester.widget<FilledButton>(find.byKey(ScanKeys.resultBack));
    expect(back.onPressed, isNull);
    expect(find.text('Please wait until the PDF is ready.'), findsOneWidget);

    await tapKey(tester, ScanKeys.pdfSkipText);

    expect(find.text('PDF saved: 2026-10-21_19-05-12.pdf'), findsOneWidget);
    expect(
      find.text(
        '2 pages have no searchable text. Their pictures are in the PDF.',
      ),
      findsOneWidget,
    );
    final backAfter = tester.widget<FilledButton>(
      find.byKey(ScanKeys.resultBack),
    );
    expect(backAfter.onPressed, isNotNull);
  });

  testWidgets('the system back button does not leave while the PDF is made', (
    tester,
  ) async {
    await pumpHome(tester);
    rig.engine.gate = Completer<void>();
    await tapKey(tester, ScanKeys.capture);
    expect(find.text('Reading the text…'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(ScanKeys.pdfStatus), findsOneWidget);
    expect(find.text('Scan saved'), findsOneWidget);

    rig.engine.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(ScanKeys.pdfOpen), findsOneWidget);
  });

  testWidgets('writing the PDF into the folder fails: clear message, photos '
      'kept, Try again works', (tester) async {
    await pumpHome(tester);
    store.failSubfolder = 'pdf';

    await tapKey(tester, ScanKeys.capture);

    expect(find.byKey(ScanKeys.pdfFailure), findsOneWidget);
    expect(
      find.textContaining('could not be written to your folder'),
      findsOneWidget,
    );
    expect(find.text('Scan saved'), findsOneWidget);
    expect(store.files('pictures'), hasLength(1));
    expect(find.byKey(ScanKeys.pdfOpen), findsNothing);

    store.failSubfolder = null;
    await tapKey(tester, ScanKeys.pdfRetry);

    expect(find.text('PDF saved: 2026-10-21_19-05-12.pdf'), findsOneWidget);
    expect(find.byKey(ScanKeys.pdfFailure), findsNothing);
    expect(store.files('pictures'), hasLength(1));
  });

  testWidgets('the writer fails: message, the screen can be left', (
    tester,
  ) async {
    await pumpHome(tester);
    pdf.builder.failWith = const ScanPdfException(ScanPdfFailure.buildFailed);

    await tapKey(tester, ScanKeys.capture);

    expect(
      find.text('The PDF could not be made. Your photos are saved.'),
      findsOneWidget,
    );
    await tapKey(tester, ScanKeys.resultBack);
    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
  });

  testWidgets('no access to the folder: the message says to choose it again', (
    tester,
  ) async {
    await pumpHome(tester);
    store.failSubfolder = 'pdf';
    store.failure = ScanStoreFailure.noAccess;

    await tapKey(tester, ScanKeys.capture);

    expect(
      find.textContaining('no longer has access to your folder'),
      findsOneWidget,
    );
  });

  testWidgets('a photo too large to prepare: the PDF cannot be made, photos '
      'saved', (tester) async {
    await pumpHome(tester);
    rig.header.fallback = null; // every header unreadable

    await tapKey(tester, ScanKeys.capture);

    expect(find.byKey(ScanKeys.pdfFailure), findsOneWidget);
    expect(find.textContaining('unreadable or too large'), findsOneWidget);
    expect(find.text('Scan saved'), findsOneWidget);
  });

  testWidgets('Greek texts', (tester) async {
    await pumpHome(tester, language: 'el');

    await tapKey(tester, ScanKeys.capture);

    expect(
      find.text('Το PDF αποθηκεύτηκε: 2026-10-21_19-05-12.pdf'),
      findsOneWidget,
    );
    expect(find.text('Άνοιγμα PDF'), findsOneWidget);
    expect(find.text('1 σελίδα, 121 KB'), findsOneWidget);
    expect(find.text('Κείμενο OCR (έλεγχος)'), findsOneWidget);
  });

  testWidgets('working copies are deleted once the PDF is stored, and the '
      'OCR check screen still works', (tester) async {
    await pumpHome(tester);
    rig.engine.respond = (_) =>
        OcrSuccess(fakeResult([fakeLine('Σύνολο 12,50', confidence: 0.97)]));

    await tapKey(tester, ScanKeys.capture);

    expect(rig.workStore.files, isEmpty);
    expect(rig.workStore.deleted, isNotEmpty);

    await tapKey(tester, ScanKeys.resultOcr);
    expect(find.text('Σύνολο 12,50'), findsOneWidget);
    expect(find.textContaining('Capture: 2000 x 2000'), findsOneWidget);
    // The boxes switch still works: it draws on the shot in the cache.
    await tapKey(tester, OcrKeys.showBoxes);
    expect(find.byKey(OcrKeys.boxesImage), findsOneWidget);
  });
}
