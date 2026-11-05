import 'dart:math' as math;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../detect/detection.dart';
import '../geometry/quad.dart';

/// A synthetic photo with its ground truth.
class EvalImage {
  EvalImage({
    required this.id,
    required this.category,
    required this.frame,
    required this.truth,
    required this.partial,
    required this.fillsFrame,
    this.document,
    this.focalPx = 0,
    int? width,
    int? height,
  }) : width = width ?? frame.width,
       height = height ?? frame.height;

  /// Size of the picture (kept when [stripped] drops the pixels).
  final int width;
  final int height;

  /// The same picture without its pixels, for results that must not keep
  /// megabytes alive (the emulator has 2 GB).
  EvalImage stripped() => EvalImage(
    id: id,
    category: category,
    frame: RgbFrame(1, 1, Uint8List(3)),
    truth: truth,
    partial: partial,
    fillsFrame: fillsFrame,
    document: document,
    focalPx: focalPx,
    width: width,
    height: height,
  );

  final String id;
  final String category;
  final RgbFrame frame;

  /// Focal length in frame pixels (as the EXIF focal length would give).
  final double focalPx;

  /// Name of the invented document on the page (see `synth/documents.dart`).
  final String? document;

  /// The true page outline (may lie partly outside the frame); null when
  /// there is no page.
  final Quad? truth;
  final bool partial;
  final bool fillsFrame;

  bool get hasDocument => truth != null;

  /// The part of the page that is inside the frame (what a crop could keep).
  List<Pt> get visibleTruth => truth == null
      ? const []
      : clipPolygon(truth!.p, Quad.frame(width, height).p);
}

/// Builds an [EvalImage] from a manifest entry and the JPEG bytes. When
/// [factor] is below 1 the picture and the truth are scaled together.
EvalImage evalImageFrom(
  Map<String, Object?> entry,
  Uint8List jpeg, {
  double factor = 1,
}) {
  var image = img.decodeJpg(jpeg)!;
  if (factor != 1) {
    image = img.copyResize(
      image,
      width: (image.width * factor).round(),
      height: (image.height * factor).round(),
      interpolation: img.Interpolation.average,
    );
  }
  final rgb = image.convert(numChannels: 3);
  final frame = RgbFrame(
    rgb.width,
    rgb.height,
    rgb.getBytes(order: img.ChannelOrder.rgb),
  );
  Quad? truth;
  final t = entry['truth'];
  if (t != null) {
    final q = Quad.fromJson((t as Map).cast<String, Object?>());
    truth = Quad([for (final p in q.p) Pt(p.x * factor, p.y * factor)]);
  }
  return EvalImage(
    id: entry['id']! as String,
    category: entry['category']! as String,
    frame: frame,
    truth: truth,
    partial: entry['partial']! as bool,
    fillsFrame: entry['fillsFrame']! as bool,
    document: entry['document'] as String?,
    focalPx: ((entry['focalPx'] as num?) ?? 0).toDouble() * factor,
  );
}

/// One detector on one image, with the numbers that do not depend on a
/// threshold.
class ImageResult {
  ImageResult({
    required this.detector,
    required EvalImage image,
    required this.detection,
  }) : image = image.stripped() {
    final truth = image.visibleTruth;
    final q = detection.quad;
    if (q != null && truth.length >= 3) {
      final inter = polygonArea(clipPolygon(truth, q.p));
      final truthArea = polygonArea(truth);
      final union = truthArea + q.area - inter;
      iou = union <= 0 ? 0 : inter / union;
      coverage = truthArea <= 0 ? 0 : inter / truthArea;
      if (!image.partial && !image.fillsFrame) {
        cornerErrorPct = _cornerError(
          q,
          image.truth!,
          image.width,
          image.height,
        );
      }
    }
  }

  final String detector;
  final EvalImage image;
  final Detection detection;

  /// Intersection over union with the visible part of the true page.
  double iou = 0;

  /// Share of the visible true page inside the detected quad (1 = nothing cut).
  double coverage = 0;
  double? cornerErrorPct;

  double get score => detection.score;

  Outcome outcomeAt(double threshold) {
    final used = detection.quad != null && score >= threshold;
    if (!used) return Outcome.fallback;
    if (!image.hasDocument) return Outcome.falsePositive;
    if (coverage < 0.98) return Outcome.cutsContent;
    return iou >= 0.9 ? Outcome.good : Outcome.loose;
  }
}

double _cornerError(Quad d, Quad truth, int width, int height) {
  final diag = math.sqrt(width.toDouble() * width + height.toDouble() * height);
  return cornerErrorPct(d, truth, diag);
}

/// What happens to the PDF for a given threshold.
enum Outcome {
  /// The detection was not trusted: the PDF gets the whole frame.
  fallback,

  /// Used, nothing of the page cut, a tight crop (IoU 0.9 or more).
  good,

  /// Used, nothing cut, but the quad is loose (IoU below 0.9).
  loose,

  /// Used and part of the visible page is outside the crop: information lost.
  cutsContent,

  /// Used on a picture that has no page.
  falsePositive,
}

List<ImageResult> runEvaluation(
  List<DocumentDetector> detectors,
  List<EvalImage> images, {
  void Function(String detector, String id, ImageResult r)? onResult,
}) {
  final out = <ImageResult>[];
  for (final d in detectors) {
    // One warm-up so the first image does not carry start-up costs.
    if (images.isNotEmpty) d.detect(images.first.frame);
    for (final image in images) {
      final r = ImageResult(
        detector: d.name,
        image: image,
        detection: d.detect(image.frame),
      );
      onResult?.call(d.name, image.id, r);
      out.add(r);
    }
  }
  return out;
}

/// Like [runEvaluation], but the pictures are loaded one at a time by
/// [loadImage] and dropped after use (the results keep no pixels).
Future<List<ImageResult>> runEvaluationLazy(
  List<DocumentDetector> detectors, {
  required int count,
  required Future<EvalImage> Function(int index) loadImage,
  void Function(String detector, String id, ImageResult r)? onResult,
}) async {
  final out = <ImageResult>[];
  for (final d in detectors) {
    // One warm-up so the first image does not carry start-up costs.
    d.detect((await loadImage(0)).frame);
    for (var i = 0; i < count; i++) {
      final image = await loadImage(i);
      final r = ImageResult(
        detector: d.name,
        image: image,
        detection: d.detect(image.frame),
      );
      onResult?.call(d.name, image.id, r);
      out.add(r);
    }
  }
  return out;
}

double _median(List<double> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

double _percentile(List<num> v, double p) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[math.min(s.length - 1, (s.length * p).floor())].toDouble();
}

String _pct(int n, int of) =>
    of == 0 ? '-' : '${(100 * n / of).toStringAsFixed(1)}%';

/// Markdown report: the table by threshold, the table by category, timings.
String formatReport(List<ImageResult> results, {List<double>? thresholds}) {
  final ts = thresholds ?? [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9];
  final detectors = results.map((r) => r.detector).toSet().toList();
  final b = StringBuffer();
  for (final d in detectors) {
    final rs = results.where((r) => r.detector == d).toList();
    final withDoc = rs.where((r) => r.image.hasDocument).toList();
    final noDoc = rs.where((r) => !r.image.hasDocument).toList();
    b.writeln(
      '### $d: ${rs.length} images (${withDoc.length} with a page, '
      '${noDoc.length} without)\n',
    );
    b.writeln(
      'Raw detection (best candidate, no threshold), pages only: '
      'IoU >= 0.9 in ${_pct(withDoc.where((r) => r.iou >= 0.9).length, withDoc.length)}, '
      'nothing cut in ${_pct(withDoc.where((r) => r.coverage >= 0.98).length, withDoc.length)}, '
      'median IoU ${_median([for (final r in withDoc) r.iou]).toStringAsFixed(3)}, '
      'median corner error '
      '${_median([for (final r in withDoc)
        if (r.cornerErrorPct != null) r.cornerErrorPct!]).toStringAsFixed(2)}% of the diagonal '
      '(pages fully in the frame).\n',
    );
    b.writeln(
      '| threshold | used | good | loose | **cuts content** | false positive (no page) | fallback (whole frame) |',
    );
    b.writeln('|---|---|---|---|---|---|---|');
    for (final t in ts) {
      final counts = <Outcome, int>{for (final o in Outcome.values) o: 0};
      for (final r in rs) {
        counts[r.outcomeAt(t)] = counts[r.outcomeAt(t)]! + 1;
      }
      final used = rs.length - counts[Outcome.fallback]!;
      b.writeln(
        '| ${t.toStringAsFixed(1)} | $used | ${counts[Outcome.good]} | '
        '${counts[Outcome.loose]} | **${counts[Outcome.cutsContent]}** | '
        '${counts[Outcome.falsePositive]} | ${counts[Outcome.fallback]} '
        '(${_pct(counts[Outcome.fallback]!, rs.length)}) |',
      );
    }
    b.writeln();
    final cats = rs.map((r) => r.image.category).toSet().toList();
    b.writeln(
      'By category at threshold 0.5 (good / loose / cuts / false positive / fallback):\n',
    );
    b.writeln(
      '| category | n | good | loose | cuts | false pos. | fallback | median IoU |',
    );
    b.writeln('|---|---|---|---|---|---|---|---|');
    for (final c in cats) {
      final cr = rs.where((r) => r.image.category == c).toList();
      int count(Outcome o) => cr.where((r) => r.outcomeAt(0.5) == o).length;
      b.writeln(
        '| $c | ${cr.length} | ${count(Outcome.good)} | ${count(Outcome.loose)} | '
        '${count(Outcome.cutsContent)} | ${count(Outcome.falsePositive)} | '
        '${count(Outcome.fallback)} | '
        '${cr.first.image.hasDocument ? _median([for (final r in cr) r.iou]).toStringAsFixed(3) : "-"} |',
      );
    }
    b.writeln();
    List<num> col(int Function(Detection) f) => [
      for (final r in rs) f(r.detection),
    ];
    b.writeln(
      'Time per image (ms), frame '
      '${rs.first.image.width}x${rs.first.image.height}: '
      'prepare median ${(_percentile(col((d) => d.microsPrepare), 0.5) / 1000).toStringAsFixed(1)}, '
      'detect median ${(_percentile(col((d) => d.microsDetect), 0.5) / 1000).toStringAsFixed(1)}, '
      'confidence median ${(_percentile(col((d) => d.microsConfidence), 0.5) / 1000).toStringAsFixed(1)}, '
      'total median ${(_percentile(col((d) => d.microsTotal), 0.5) / 1000).toStringAsFixed(1)}, '
      'total p95 ${(_percentile(col((d) => d.microsTotal), 0.95) / 1000).toStringAsFixed(1)}.\n',
    );
  }
  return b.toString();
}

/// One CSV line per image and detector, for the record.
String csvHeader() =>
    'detector,id,category,hasDocument,partial,fillsFrame,score,area,angle,ratio,'
    'support,contrast,iou,coverage,cornerErrPct,candidates,msPrepare,msDetect,msConfidence';

String csvLine(ImageResult r) {
  final c = r.detection.confidence;
  String f(double v) => v.toStringAsFixed(3);
  return [
    r.detector,
    r.image.id,
    r.image.category,
    r.image.hasDocument,
    r.image.partial,
    r.image.fillsFrame,
    f(r.score),
    f(c.area),
    f(c.angle),
    f(c.ratio),
    f(c.support),
    f(c.contrast),
    f(r.iou),
    f(r.coverage),
    r.cornerErrorPct == null ? '' : f(r.cornerErrorPct!),
    r.detection.candidates,
    (r.detection.microsPrepare / 1000).toStringAsFixed(1),
    (r.detection.microsDetect / 1000).toStringAsFixed(1),
    (r.detection.microsConfidence / 1000).toStringAsFixed(1),
  ].join(',');
}
