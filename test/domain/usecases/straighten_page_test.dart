import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/page_crop_outcome.dart';
import 'package:one_click_scan/domain/entities/upright_image.dart';
import 'package:one_click_scan/domain/imaging/page_crop_config.dart';
import 'package:one_click_scan/domain/ocr/ocr_cancellation.dart';
import 'package:one_click_scan/domain/ocr/ocr_config.dart';
import 'package:one_click_scan/domain/usecases/straighten_page.dart';

import '../../support/ocr_fakes.dart';

const _image = UprightImage(
  path: 'work/upright_0.jpg',
  width: 1500,
  height: 2000,
  sourceWidth: 3000,
  sourceHeight: 4000,
  focalLength35mm: 26,
);

void main() {
  late InMemoryOcrWorkStore store;
  late FakeCropper cropper;
  late StraightenPage straighten;

  setUp(() {
    store = InMemoryOcrWorkStore()..files.add(_image.path);
    cropper = FakeCropper();
    straighten = StraightenPage(cropper: cropper, workStore: store);
  });

  test(
    'a page that was found becomes the new picture, the old file goes',
    () async {
      final result = await straighten(_image);

      expect(result.outcome, isA<PageCropped>());
      expect(result.image.path, isNot(_image.path));
      expect((result.image.width, result.image.height), (1200, 1700));
      // The capture facts and the focal length travel with the picture.
      expect(result.image.sourceWidth, 3000);
      expect(result.image.sourceHeight, 4000);
      expect(result.image.focalLength35mm, 26);
      expect(store.files, {result.image.path});
      expect(store.deleted, [_image.path]);
    },
  );

  test(
    'the cropper is given the rules of the config and the focal length',
    () async {
      await straighten(_image);

      final call = cropper.calls.single;
      expect(call.source, _image.path);
      expect(call.maxSide, OcrConfig.workingSide);
      expect(call.jpegQuality, OcrConfig.workingJpegQuality);
      expect(call.focalLength35mm, 26);
      expect(call.timeout, PageCropConfig.timeout);
    },
  );

  for (final reason in WholeFrameReason.values) {
    test(
      'whole frame ($reason): the same picture, no new file is left',
      () async {
        cropper.outcome = PageWholeFrame(reason);

        final result = await straighten(_image);

        expect(result.image, _image);
        expect(result.outcome, PageWholeFrame(reason));
        expect(store.files, {_image.path}, reason: 'only the working copy');
        expect(store.deleted, hasLength(1)); // the unused target
        expect(store.deleted.single, isNot(_image.path));
      },
    );
  }

  test(
    'an exception in the cropper is the whole frame, never thrown',
    () async {
      cropper.throwWith = StateError('boom');

      final result = await straighten(_image);

      expect(result.image, _image);
      expect(result.outcome, const PageWholeFrame(WholeFrameReason.failed));
      expect(store.files, {_image.path});
    },
  );

  test('an exception in the store is the whole frame too', () async {
    straighten = StraightenPage(cropper: cropper, workStore: _FailingStore());

    final result = await straighten(_image);

    expect(result.image, _image);
    expect(result.outcome, isA<PageWholeFrame>());
  });

  test('the cancellation is handed to the cropper', () async {
    final cancel = OcrCancellation();

    await straighten(_image, cancellation: cancel);

    expect(cropper.calls.single.cancellation, same(cancel));
  });
}

class _FailingStore extends InMemoryOcrWorkStore {
  @override
  Future<String> newImagePath() async => throw StateError('disk full');
}
