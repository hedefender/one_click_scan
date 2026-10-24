import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/ocr_progress.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/features/ocr/ocr_keys.dart';
import 'package:one_click_scan/features/ocr/ocr_result_cubit.dart';
import 'package:one_click_scan/features/ocr/ocr_result_page.dart';
import 'package:one_click_scan/presentation/l10n/app_strings.dart';

import '../../support/ocr_fakes.dart';

void main() {
  late OcrTestRig rig;
  late OcrSession session;

  Future<void> pumpPage(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: BlocProvider<OcrResultCubit>(
          create: (_) => OcrResultCubit(session),
          child: const OcrResultPage(),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    rig = OcrTestRig();
    session = rig.recognize.start(packId: 'greek');
  });

  tearDown(() => session.dispose());

  group('while a page is being read', () {
    testWidgets('progress is text ("line 12 of 51") and a still bar', (
      tester,
    ) async {
      rig.engine
        ..gate = Completer<void>()
        ..progress = const [
          OcrProgress(OcrStage.recognizing, done: 12, total: 51),
        ];
      session.add('p1', 'p1.jpg');
      await pumpPage(tester);
      await tester.pump();

      expect(find.text('Reading line 12 of 51'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(OcrKeys.progressBar),
      );
      expect(bar.value, closeTo(12 / 51, 1e-9));
    });

    testWidgets('nothing animates continuously: no spinner, bar is '
        'determinate', (tester) async {
      rig.engine.gate = Completer<void>();
      session.add('p1', 'p1.jpg');
      await pumpPage(tester);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(OcrKeys.progressBar),
      );
      expect(bar.value, isNotNull);
      // No frame is scheduled by the page itself: the app is idle.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a queued page says it waits', (tester) async {
      rig.engine.gate = Completer<void>();
      session
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg');
      await pumpPage(tester);
      await tester.pump();

      await tester.tap(find.byKey(OcrKeys.nextPage));
      await tester.pump();

      expect(find.text('Waiting for the previous page'), findsOneWidget);
      expect(find.byKey(OcrKeys.pageLabel), findsOneWidget);
      expect(find.text('Page 2 of 2'), findsOneWidget);
    });

    testWidgets('models loading is named', (tester) async {
      rig.engine
        ..gate = Completer<void>()
        ..progress = const [OcrProgress(OcrStage.loadingModels)];
      session.add('p1', 'p1.jpg');
      await pumpPage(tester);
      await tester.pump();

      expect(find.text('Loading the language models'), findsOneWidget);
    });
  });

  group('the result of a page', () {
    setUp(() {
      rig.engine.respond = (_) => OcrSuccess(
        fakeResult([
          fakeLine('Total 45,90', confidence: 0.98, row: 0, x: 0.1, y: 0.2),
          fakeLine('EUR', confidence: 0.91, row: 0, x: 0.6, y: 0.2),
          fakeLine('~~ scribble ~~', confidence: 0.12, row: 1),
        ], duration: const Duration(milliseconds: 1840)),
      );
    });

    Future<void> readPage(WidgetTester tester) async {
      session
        ..add('p1', 'p1.jpg')
        ..close();
      await pumpPage(tester);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('each line with its confidence and position', (tester) async {
      await readPage(tester);

      expect(find.text('Total 45,90'), findsOneWidget);
      expect(find.text('98% · (0.10, 0.20)'), findsOneWidget);
      expect(find.text('91% · (0.60, 0.20)'), findsOneWidget);
    });

    testWidgets('a filtered line has its own label and colour', (tester) async {
      await readPage(tester);

      expect(
        find.text('12% · (0.10, 0.10) · filtered, low confidence'),
        findsOneWidget,
      );
      final title = tester.widget<Text>(find.text('~~ scribble ~~'));
      expect(title.style?.decoration, TextDecoration.lineThrough);
      final kept = tester.widget<Text>(find.text('Total 45,90'));
      expect(kept.style?.decoration, isNull);
    });

    testWidgets('the summary shows pack, time, sizes and counts', (
      tester,
    ) async {
      await readPage(tester);

      expect(find.text('Language pack: Greek + English'), findsOneWidget);
      expect(find.text('Time: 1.8 s'), findsOneWidget);
      expect(find.text('Working image: 1000 x 1400 px'), findsOneWidget);
      expect(find.text('Capture: 2000 x 2000 px (4.0 MP)'), findsOneWidget);
      expect(find.text('Boxes: 3 (filtered: 1)'), findsOneWidget);
    });

    testWidgets('Copy puts the visible text on the clipboard, not the '
        'filtered line', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await readPage(tester);

      await tester.tap(find.byKey(OcrKeys.copy));
      await tester.pump();

      expect(copied, 'Total 45,90 EUR');
      expect(find.text('Text copied.'), findsOneWidget);
    });

    testWidgets('the boxes can be shown over the image', (tester) async {
      await readPage(tester);
      expect(find.byKey(OcrKeys.boxesImage), findsNothing);

      await tester.tap(find.byKey(OcrKeys.showBoxes));
      await tester.pump();

      expect(find.byKey(OcrKeys.boxesImage), findsOneWidget);
    });

    testWidgets('no text on the page says so', (tester) async {
      rig.engine.respond = (_) => OcrSuccess(fakeResult(const []));
      await readPage(tester);

      expect(find.byKey(OcrKeys.noText), findsOneWidget);
    });
  });

  group('layout', () {
    for (final size in const [
      Size(360, 640),
      Size(640, 360),
      Size(1280, 600),
    ]) {
      testWidgets(
        'no overflow at ${size.width.toInt()} x ${size.height.toInt()}',
        (tester) async {
          rig.engine.respond = (_) => OcrSuccess(
            fakeResult([
              for (var i = 0; i < 30; i++)
                fakeLine(
                  'A very long line of text number $i that has to wrap on a '
                  'narrow screen without overflowing the row',
                  confidence: i.isEven ? 0.95 : 0.2,
                  row: i,
                ),
            ]),
          );
          session
            ..add('p1', 'p1.jpg')
            ..add('p2', 'p2.jpg')
            ..close();
          await pumpPage(tester);
          tester.view.physicalSize = size;
          await tester.pump();
          await tester.pump();
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byKey(OcrKeys.copy), findsOneWidget);
          expect(find.byKey(OcrKeys.nextPage), findsOneWidget);
        },
      );
    }
  });

  group('pages', () {
    testWidgets('two pages: switch with the arrows, each shows its own text', (
      tester,
    ) async {
      rig.engine.respond = (image) => OcrSuccess(
        fakeResult([fakeLine('text of ${image.path.split('_').last}')]),
      );
      session
        ..add('p1', 'p1.jpg')
        ..add('p2', 'p2.jpg')
        ..close();
      await pumpPage(tester);
      await tester.pump();
      await tester.pump();

      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('text of 1.jpg'), findsOneWidget);
      await tester.tap(find.byKey(OcrKeys.nextPage));
      await tester.pump();
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('text of 2.jpg'), findsOneWidget);
      await tester.tap(find.byKey(OcrKeys.previousPage));
      await tester.pump();
      expect(find.text('text of 1.jpg'), findsOneWidget);
    });

    testWidgets('one page has no page switcher', (tester) async {
      session
        ..add('p1', 'p1.jpg')
        ..close();
      await pumpPage(tester);
      await tester.pump();

      expect(find.byKey(OcrKeys.pageLabel), findsNothing);
    });
  });

  group('failures are shown as messages', () {
    Future<void> failWith(WidgetTester tester, OcrOutcome outcome) async {
      rig.engine.respond = (_) => outcome;
      session
        ..add('p1', 'p1.jpg')
        ..close();
      await pumpPage(tester);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('timeout', (tester) async {
      await failWith(tester, const OcrTimedOut(Duration(seconds: 45)));

      expect(
        find.text('Reading this page took too long and was stopped.'),
        findsOneWidget,
      );
      expect(find.byKey(OcrKeys.copy), findsNothing);
    });

    testWidgets('too large', (tester) async {
      await failWith(tester, const OcrFailed(OcrFailureReason.imageTooLarge));

      expect(
        find.text('The picture is too large to read (over 50 megapixels).'),
        findsOneWidget,
      );
    });

    testWidgets('missing model', (tester) async {
      await failWith(
        tester,
        const OcrFailed(OcrFailureReason.modelUnavailable),
      );

      expect(find.textContaining('missing or damaged'), findsOneWidget);
    });

    testWidgets('cancelled', (tester) async {
      await failWith(tester, const OcrCancelled());

      expect(find.text('Reading was cancelled.'), findsOneWidget);
    });
  });

  testWidgets('Greek strings', (tester) async {
    rig.engine
      ..gate = Completer<void>()
      ..progress = const [OcrProgress(OcrStage.recognizing, done: 3, total: 9)];
    session.add('p1', 'p1.jpg');
    await pumpPage(tester, locale: const Locale('el'));
    await tester.pump();

    expect(find.text('Κείμενο OCR'), findsOneWidget);
    expect(find.text('Ανάγνωση γραμμής 3 από 9'), findsOneWidget);
  });
}
