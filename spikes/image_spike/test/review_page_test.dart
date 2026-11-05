import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_spike/phone/pipeline.dart';
import 'package:image_spike/phone/review_page.dart';
import 'package:image_spike/phone/verdicts.dart';

Uint8List _jpg() => img.encodeJpg(img.Image(width: 8, height: 8));

Future<PhotoResult> _fake(String path, Engine engine) async => PhotoResult(
  frameJpg: _jpg(),
  afterJpg: _jpg(),
  afterFlatJpg: _jpg(),
  used: path.contains('sure'),
  score: 0.8,
  otherScore: 0.7,
  frameWidth: 8,
  frameHeight: 8,
  sourceWidth: 4000,
  sourceHeight: 3000,
  focalPx: 0,
  decodeMs: 1,
  detectMs: 2,
  warpMs: 3,
  flatMs: 4,
);

void main() {
  testWidgets('shows original and after, records yes and no, then closes', (
    tester,
  ) async {
    final store = VerdictStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReviewPage(
                  paths: const ['a_sure.jpg', 'b.jpg'],
                  engine: Engine.dart,
                  store: store,
                  ocr: null,
                  process: _fake,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Πρωτότυπο'), findsOneWidget);
    expect(find.text('Μετά (κομμένο)'), findsOneWidget);
    await tester.tap(find.text('ΝΑΙ'));
    await tester.pumpAndSettle();
    expect(find.text('Μετά (ολόκληρο καρέ)'), findsOneWidget);
    await tester.tap(find.text('ΟΧΙ'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(store.verdicts.map((v) => v.good), [true, false]);
    expect(store.verdicts.map((v) => v.used), [true, false]);
  });
}
