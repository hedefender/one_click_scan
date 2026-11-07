import 'dart:async';

import 'package:one_click_scan/domain/entities/ocr_line.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/ocr_progress.dart';
import 'package:one_click_scan/domain/entities/ocr_result.dart';
import 'package:one_click_scan/domain/entities/page_crop_outcome.dart';
import 'package:one_click_scan/domain/entities/upright_image.dart';
import 'package:one_click_scan/domain/imaging/quad.dart';
import 'package:one_click_scan/domain/ocr/ocr_cancellation.dart';
import 'package:one_click_scan/domain/ocr/ocr_config.dart';
import 'package:one_click_scan/domain/ports/image_header_reader.dart';
import 'package:one_click_scan/domain/ports/ocr_engine.dart';
import 'package:one_click_scan/domain/ports/ocr_work_store.dart';
import 'package:one_click_scan/domain/ports/light_enhancer.dart';
import 'package:one_click_scan/domain/ports/page_cropper.dart';
import 'package:one_click_scan/domain/usecases/enhance_page_light.dart';
import 'package:one_click_scan/domain/ports/upright_image_maker.dart';
import 'package:one_click_scan/domain/usecases/prepare_image_for_ocr.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/domain/usecases/straighten_page.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';

/// A square quad around (x, y).
List<OcrPoint> quadAt(double x, double y, [double size = 0.05]) => [
  OcrPoint(x, y),
  OcrPoint(x + size, y),
  OcrPoint(x + size, y + size),
  OcrPoint(x, y + size),
];

OcrLine fakeLine(
  String text, {
  double confidence = 0.95,
  int row = 0,
  double x = 0.1,
  double y = 0.1,
}) => OcrLine(text: text, confidence: confidence, quad: quadAt(x, y), row: row);

OcrResult fakeResult(
  List<OcrLine> lines, {
  String packId = 'greek',
  Duration duration = const Duration(milliseconds: 900),
}) => OcrResult(
  lines: lines,
  packId: packId,
  duration: duration,
  imageWidth: 1000,
  imageHeight: 1400,
);

/// Scripted engine: each call returns what [respond] says, optionally after
/// a delay the test controls with a completer.
class FakeOcrEngine implements OcrEngine {
  FakeOcrEngine({this.respond});

  /// Maps the image path to an outcome; default is a one line success.
  FutureOr<OcrOutcome> Function(UprightImage image)? respond;

  /// When set, every call waits for it first (to hold a page "in flight").
  Completer<void>? gate;

  /// Reports this progress before answering.
  List<OcrProgress> progress = const [];

  final List<String> recognized = [];
  final List<String> preloaded = [];
  int releaseCalls = 0;
  int disposeCalls = 0;
  int running = 0;
  int maxRunning = 0;

  @override
  Future<void> preload(String packId) async => preloaded.add(packId);

  @override
  Future<OcrOutcome> recognize(
    UprightImage image, {
    required String packId,
    Duration timeout = OcrConfig.pageTimeout,
    OcrCancellation? cancellation,
    void Function(OcrProgress progress)? onProgress,
  }) async {
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      recognized.add(image.path);
      for (final p in progress) {
        onProgress?.call(p);
      }
      final g = gate;
      if (g != null) {
        await Future.any([g.future, ?cancellation?.whenCancelled]);
        if (cancellation?.isCancelled ?? false) return const OcrCancelled();
      }
      final custom = respond;
      if (custom != null) return await custom(image);
      return OcrSuccess(
        fakeResult([fakeLine('line of ${image.path}')], packId: packId),
      );
    } finally {
      running--;
    }
  }

  @override
  Future<void> release() async => releaseCalls++;

  @override
  Future<void> dispose() async => disposeCalls++;
}

/// One call of [FakeCropper].
class CropCall {
  const CropCall({
    required this.source,
    required this.target,
    required this.maxSide,
    required this.jpegQuality,
    required this.focalLength35mm,
    required this.timeout,
    required this.cancellation,
  });

  final String source;
  final String target;
  final int maxSide;
  final int jpegQuality;
  final int? focalLength35mm;
  final Duration timeout;
  final OcrCancellation? cancellation;
}

/// Scripted page cropper: no pixels, only the outcomes.
class FakeCropper implements PageCropper {
  /// The answer when [respond] is not set: a crop of 1200 x 1700.
  PageCropOutcome outcome = PageCropped(
    quad: Quad.frame(1200, 1700),
    confidence: 0.9,
    width: 1200,
    height: 1700,
  );

  /// The answer by the path of the picture being cropped.
  PageCropOutcome Function(String source)? respond;

  /// Thrown instead of an answer.
  Object? throwWith;

  /// While set, a crop waits for it (to hold a page "in the crop"); a cancel
  /// ends the wait with the whole frame, as the real cropper does.
  Completer<void>? gate;

  final List<CropCall> calls = [];
  int running = 0;
  int maxRunning = 0;

  @override
  Future<PageCropOutcome> crop({
    required String source,
    required String target,
    required int maxSide,
    required int jpegQuality,
    required int? focalLength35mm,
    required Duration timeout,
    OcrCancellation? cancellation,
  }) async {
    calls.add(
      CropCall(
        source: source,
        target: target,
        maxSide: maxSide,
        jpegQuality: jpegQuality,
        focalLength35mm: focalLength35mm,
        timeout: timeout,
        cancellation: cancellation,
      ),
    );
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      final failure = throwWith;
      if (failure != null) throw failure;
      final g = gate;
      if (g != null) {
        await Future.any([g.future, ?cancellation?.whenCancelled]);
        if (cancellation?.isCancelled ?? false) {
          return const PageWholeFrame(WholeFrameReason.cancelled);
        }
      }
      return respond?.call(source) ?? outcome;
    } finally {
      running--;
    }
  }
}

class InMemoryOcrWorkStore implements OcrWorkStore {
  final Set<String> files = {};
  final List<String> deleted = [];
  var _n = 0;
  bool purged = false;

  @override
  Future<String> newImagePath() async {
    final path = 'work/upright_${++_n}.jpg';
    files.add(path);
    return path;
  }

  @override
  Future<void> delete(String path) async {
    files.remove(path);
    deleted.add(path);
  }

  @override
  Future<void> purgeAll() async {
    files.clear();
    purged = true;
  }
}

/// Header by path; unknown paths are unreadable.
class FakeHeaderReader implements ImageHeaderReader {
  FakeHeaderReader([Map<String, ImageHeader>? headers])
    : headers = headers ?? {};

  final Map<String, ImageHeader> headers;

  /// Header for every path not listed (a 4 MP photo by default).
  ImageHeader? fallback = const ImageHeader(
    width: 2000,
    height: 2000,
    orientation: 1,
  );

  @override
  Future<ImageHeader?> read(String path) async => headers[path] ?? fallback;
}

class FakeMaker implements UprightImageMaker {
  FakeMaker(this.name);

  final String name;
  final List<String> sources = [];
  UprightImageException? failWith;
  UprightPixels pixels = const UprightPixels(width: 1500, height: 2000);

  @override
  Future<UprightPixels> make({
    required String source,
    required String target,
    required int maxSide,
    required int jpegQuality,
  }) async {
    sources.add(source);
    final failure = failWith;
    if (failure != null) throw failure;
    return pixels;
  }
}

/// Scripted light enhancer: writes nothing, only says whether it "wrote".
class FakeEnhancer implements LightEnhancer {
  bool succeed = true;
  Completer<void>? gate;
  final List<String> sources = [];
  final List<String> targets = [];

  @override
  Future<bool> enhance({
    required String source,
    required String target,
    required int jpegQuality,
    required Duration timeout,
    OcrCancellation? cancellation,
  }) async {
    sources.add(source);
    targets.add(target);
    final g = gate;
    if (g != null) await g.future;
    return succeed;
  }
}

/// Everything a session test needs, wired like the real container.
class OcrTestRig {
  OcrTestRig({FakeOcrEngine? engine, this.cropper, this.enhancer})
    : engine = engine ?? FakeOcrEngine(),
      header = FakeHeaderReader(),
      dartMaker = FakeMaker('dart'),
      nativeMaker = FakeMaker('native'),
      workStore = InMemoryOcrWorkStore() {
    prepare = PrepareImageForOcr(
      headerReader: header,
      dartMaker: dartMaker,
      nativeMaker: nativeMaker,
      workStore: workStore,
    );
    recognize = RecognizePages(
      engine: this.engine,
      prepare: prepare,
      workStore: workStore,
      straighten: cropper == null
          ? null
          : StraightenPage(cropper: cropper!, workStore: workStore),
      enhance: enhancer == null
          ? null
          : EnhancePageLight(enhancer: enhancer!, workStore: workStore),
    );
  }

  /// The light correction; none unless a test gives one.
  final FakeEnhancer? enhancer;

  /// The crop of the pages; none unless a test gives one.
  final PageCropper? cropper;

  /// The same fakes as an `OcrServices` bundle, for `buildTestContainer`.
  OcrServices get services => OcrServices(
    engine: engine,
    workStore: workStore,
    headerReader: header,
    dartMaker: dartMaker,
    nativeMaker: nativeMaker,
    cropper: cropper,
    enhancer: enhancer,
  );

  final FakeOcrEngine engine;
  final FakeHeaderReader header;
  final FakeMaker dartMaker;
  final FakeMaker nativeMaker;
  final InMemoryOcrWorkStore workStore;
  late final PrepareImageForOcr prepare;
  late final RecognizePages recognize;
}
