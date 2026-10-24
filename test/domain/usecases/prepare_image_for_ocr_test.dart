import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/ports/image_header_reader.dart';
import 'package:one_click_scan/domain/ports/upright_image_maker.dart';
import 'package:one_click_scan/domain/usecases/prepare_image_for_ocr.dart';

import '../../support/ocr_fakes.dart';

ImageHeader header(int w, int h, [int orientation = 1]) =>
    ImageHeader(width: w, height: h, orientation: orientation);

void main() {
  late OcrTestRig rig;

  setUp(() => rig = OcrTestRig());

  test(
    'a small photo goes to the Dart maker, never to the native one',
    () async {
      rig.header.headers['a.jpg'] = header(2000, 2000); // 4 MP

      final image = await rig.prepare('a.jpg');

      expect(rig.dartMaker.sources, ['a.jpg']);
      expect(rig.nativeMaker.sources, isEmpty);
      expect(image.path, startsWith('work/'));
    },
  );

  test('a 12 MP photo goes to the native maker', () async {
    rig.header.headers['b.jpg'] = header(4000, 3000);

    await rig.prepare('b.jpg');

    expect(rig.nativeMaker.sources, ['b.jpg']);
    expect(rig.dartMaker.sources, isEmpty);
  });

  test('the size comes from the decoded pixels, the capture size from the '
      'header', () async {
    rig.header.headers['c.jpg'] = header(4000, 3000, 6);
    rig.nativeMaker.pixels = const UprightPixels(width: 1920, height: 2560);

    final image = await rig.prepare('c.jpg');

    expect(image.width, 1920);
    expect(image.height, 2560);
    expect(image.sourceWidth, 4000);
    expect(image.sourceHeight, 3000);
    expect(image.sourceMegapixels, 12.0);
  });

  test('above 50 MP nothing is decoded and no file is made', () async {
    rig.header.headers['huge.jpg'] = header(12240, 16320); // 200 MP

    await expectLater(
      rig.prepare('huge.jpg'),
      throwsA(
        isA<ImagePreparationException>().having(
          (e) => e.reason,
          'reason',
          OcrFailureReason.imageTooLarge,
        ),
      ),
    );

    expect(rig.dartMaker.sources, isEmpty);
    expect(rig.nativeMaker.sources, isEmpty);
    expect(rig.workStore.files, isEmpty);
  });

  test('a file that is not an image is unreadable', () async {
    rig.header.fallback = null;

    await expectLater(
      rig.prepare('notes.txt'),
      throwsA(
        isA<ImagePreparationException>().having(
          (e) => e.reason,
          'reason',
          OcrFailureReason.imageUnreadable,
        ),
      ),
    );
  });

  test('a maker failure removes the half written file', () async {
    rig.header.headers['d.jpg'] = header(2000, 2000);
    rig.dartMaker.failWith = const UprightImageException('unreadable');

    await expectLater(
      rig.prepare('d.jpg'),
      throwsA(
        isA<ImagePreparationException>().having(
          (e) => e.reason,
          'reason',
          OcrFailureReason.imageUnreadable,
        ),
      ),
    );

    expect(rig.workStore.files, isEmpty);
    expect(rig.workStore.deleted, hasLength(1));
  });

  test('an out of memory in the native decode is an engine error', () async {
    rig.header.headers['e.jpg'] = header(4000, 3000);
    rig.nativeMaker.failWith = const UprightImageException('outOfMemory');

    await expectLater(
      rig.prepare('e.jpg'),
      throwsA(
        isA<ImagePreparationException>().having(
          (e) => e.reason,
          'reason',
          OcrFailureReason.engineError,
        ),
      ),
    );
    expect(rig.workStore.files, isEmpty);
  });
}
