import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'ocr_engine.dart';

/// PP-OCRv5 (ONNX Runtime through `flutter_onnxruntime`). Everything around
/// the two networks is hand-written here: resize/normalise, DB post-processing
/// (connected components + PCA box instead of OpenCV contours + minAreaRect),
/// unclip, rotated crops, CTC greedy decoding. This is the "custom code" whose
/// cost the spike has to measure.
class PaddleEngine implements SpikeOcrEngine {
  PaddleEngine(this.recKey, {this.detSideLimit = 960, this.applyExif = false});

  /// `greek`, `latin` or `eslav` (asset names `rec_<key>.onnx`).
  final String recKey;
  final int detSideLimit;

  /// Bake the EXIF orientation into the pixels before detection. The default
  /// mimics a plain decoder, which ignores the tag.
  final bool applyExif;

  static final _ort = OnnxRuntime();
  static OrtSession? _det;
  static final _rec = <String, OrtSession>{};
  static final _dicts = <String, List<String>>{};

  static const _recHeight = 48;
  static const _maxRecWidth = 2048;
  static const _detThresh = 0.3;
  static const _boxThresh = 0.6;
  static const _unclipRatio = 1.5;

  @override
  String get id => 'paddle_$recKey';

  @override
  String get languages => recKey;

  @override
  Future<void> prepare() async {
    _det ??= await _ort.createSessionFromAsset(
      'assets/models/det_mobile.onnx',
      options: OrtSessionOptions(intraOpNumThreads: 4),
    );
    if (!_rec.containsKey(recKey)) {
      _rec[recKey] = await _ort.createSessionFromAsset(
        'assets/models/rec_$recKey.onnx',
        options: OrtSessionOptions(intraOpNumThreads: 4),
      );
      final dict = await rootBundle.loadString(
        'assets/models/dict_$recKey.txt',
      );
      final chars = dict
          .split('\n')
          .map((l) => l.replaceAll('\r', ''))
          .toList();
      if (chars.isNotEmpty && chars.last.isEmpty) chars.removeLast();
      _dicts[recKey] = ['', ...chars, ' '];
    }
  }

  @override
  Future<OcrResult> recognize(String imagePath) async {
    final total = Stopwatch()..start();
    try {
      await prepare();
      final t0 = total.elapsedMilliseconds;
      final bytes = await File(imagePath).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) throw StateError('decode');
      if (applyExif) image = img.bakeOrientation(image);
      if (image.numChannels == 4) image = image.convert(numChannels: 3);
      final rgb = image.getBytes(order: img.ChannelOrder.rgb);
      final t1 = total.elapsedMilliseconds;

      final boxes = await _detect(image, rgb);
      final t2 = total.elapsedMilliseconds;

      final recSession = _rec[recKey]!;
      final dict = _dicts[recKey]!;
      final items = <_Item>[];
      var recNs = 0;
      for (final box in boxes) {
        final crop = _crop(rgb, image.width, image.height, box);
        final (text, conf) = await _recognizeCrop(recSession, dict, crop);
        recNs++;
        if (text.trim().isEmpty) continue;
        items.add(_Item(box, text, conf));
      }
      total.stop();
      final lines = _toLines(items);
      final confs = items.map((i) => i.conf).toList();
      return OcrResult(
        text: lines.map((l) => l.text).join('\n'),
        elapsedMs: total.elapsedMilliseconds,
        lines: [
          for (final i in items)
            OcrLine(i.text, i.box.bounds, confidence: i.conf),
        ],
        confidence: confs.isEmpty
            ? null
            : confs.reduce((a, b) => a + b) / confs.length,
        breakdown: {
          'decode': t1 - t0,
          'detect': t2 - t1,
          'recognize': total.elapsedMilliseconds - t2,
          'boxes': recNs,
        },
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('paddle error ${e.runtimeType}: $e\n$st');
      return OcrResult(
        text: '',
        elapsedMs: total.elapsedMilliseconds,
        error: e.runtimeType.toString(),
      );
    }
  }

  // -------------------------------------------------------------- detection

  Future<List<_Box>> _detect(img.Image image, Uint8List rgb) async {
    final w = image.width, h = image.height;
    final scale = math.min(1.0, detSideLimit / math.max(w, h));
    int round32(double v) => math.max(32, (v / 32).round() * 32);
    final dw = round32(w * scale), dh = round32(h * scale);

    // Bilinear resample straight from the RGB bytes into the tensor
    // (B, G, R order, ImageNet mean/std as PaddleOCR does).
    const mean = [0.406, 0.456, 0.485]; // B, G, R
    const std = [0.225, 0.224, 0.229];
    final input = Float32List(3 * dh * dw);
    final sx = w / dw, sy = h / dh;
    for (var y = 0; y < dh; y++) {
      for (var x = 0; x < dw; x++) {
        final px = _sample(
          rgb,
          w,
          h,
          (x + 0.5) * sx - 0.5,
          (y + 0.5) * sy - 0.5,
        );
        final o = y * dw + x;
        input[o] = (px[2] / 255 - mean[0]) / std[0];
        input[dh * dw + o] = (px[1] / 255 - mean[1]) / std[1];
        input[2 * dh * dw + o] = (px[0] / 255 - mean[2]) / std[2];
      }
    }

    final det = _det!;
    final tensor = await OrtValue.fromList(input, [1, 3, dh, dw]);
    final out = await det.run({det.inputNames.first: tensor});
    final map = out[det.outputNames.first]!;
    final flat = await map.asFlattenedList();
    await tensor.dispose();
    await map.dispose();
    final prob = Float32List(dh * dw);
    for (var i = 0; i < prob.length; i++) {
      prob[i] = (flat[i] as num).toDouble();
    }
    return _boxesFromMap(prob, dw, dh, w / dw, h / dh);
  }

  List<_Box> _boxesFromMap(
    Float32List prob,
    int w,
    int h,
    double toX,
    double toY,
  ) {
    final seen = Uint8List(w * h);
    final stack = Int32List(w * h);
    final boxes = <_Box>[];
    for (var start = 0; start < prob.length; start++) {
      if (seen[start] != 0 || prob[start] <= _detThresh) continue;
      var sp = 0;
      stack[sp++] = start;
      seen[start] = 1;
      final xs = <int>[];
      final ys = <int>[];
      var sum = 0.0;
      while (sp > 0) {
        final p = stack[--sp];
        final px = p % w, py = p ~/ w;
        xs.add(px);
        ys.add(py);
        sum += prob[p];
        for (var dy = -1; dy <= 1; dy++) {
          final ny = py + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = px + dx;
            if (nx < 0 || nx >= w) continue;
            final q = ny * w + nx;
            if (seen[q] == 0 && prob[q] > _detThresh) {
              seen[q] = 1;
              stack[sp++] = q;
            }
          }
        }
      }
      if (xs.length < 12) continue;
      if (sum / xs.length < _boxThresh) continue;
      final box = _orientedBox(xs, ys);
      if (math.min(box.w, box.h) < 3) continue;
      // Unclip: grow the shrunk text kernel back (DB post-processing).
      final d = box.w * box.h * _unclipRatio / (2 * (box.w + box.h));
      final grown = _Box(
        box.cx,
        box.cy,
        box.w + 2 * d,
        box.h + 2 * d,
        box.angle,
      );
      boxes.add(grown.scaled(toX, toY));
    }
    return _sortBoxes(boxes);
  }

  _Box _orientedBox(List<int> xs, List<int> ys) {
    final n = xs.length;
    var mx = 0.0, my = 0.0;
    for (var i = 0; i < n; i++) {
      mx += xs[i];
      my += ys[i];
    }
    mx /= n;
    my /= n;
    var cxx = 0.0, cyy = 0.0, cxy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = xs[i] - mx, dy = ys[i] - my;
      cxx += dx * dx;
      cyy += dy * dy;
      cxy += dx * dy;
    }
    var angle = 0.5 * math.atan2(2 * cxy, cxx - cyy);
    var ux = math.cos(angle), uy = math.sin(angle);
    var umin = 1e9, umax = -1e9, vmin = 1e9, vmax = -1e9;
    for (var i = 0; i < n; i++) {
      final dx = xs[i] - mx, dy = ys[i] - my;
      final u = dx * ux + dy * uy;
      final v = -dx * uy + dy * ux;
      umin = math.min(umin, u);
      umax = math.max(umax, u);
      vmin = math.min(vmin, v);
      vmax = math.max(vmax, v);
    }
    // Make "u" the long axis: rotate by 90 degrees. The new u axis is the old
    // v axis, the new v axis is the old u axis with its sign flipped.
    if (vmax - vmin > umax - umin) {
      angle += math.pi / 2;
      ux = math.cos(angle);
      uy = math.sin(angle);
      final (oumin, oumax) = (umin, umax);
      umin = vmin;
      umax = vmax;
      vmin = -oumax;
      vmax = -oumin;
    }
    final cu = (umin + umax) / 2, cv = (vmin + vmax) / 2;
    final cx = mx + cu * ux - cv * uy;
    final cy = my + cu * uy + cv * ux;
    // Keep text direction left to right.
    while (angle > math.pi / 2) {
      angle -= math.pi;
    }
    while (angle < -math.pi / 2) {
      angle += math.pi;
    }
    return _Box(cx + 0.5, cy + 0.5, umax - umin + 1, vmax - vmin + 1, angle);
  }

  /// Reading order: rows first, then left to right inside a row. The rows are
  /// measured perpendicular to the median text direction, so a page tilted by
  /// a few degrees still groups its lines correctly.
  List<_Box> _sortBoxes(List<_Box> boxes) {
    final angles = [
      for (final b in boxes)
        if (b.w > 2 * b.h) b.angle,
    ]..sort();
    final skew = angles.isEmpty ? 0.0 : angles[angles.length ~/ 2];
    final cs = math.cos(skew), sn = math.sin(skew);
    double perp(_Box b) => -b.cx * sn + b.cy * cs;
    double along(_Box b) => b.cx * cs + b.cy * sn;
    boxes.sort((a, b) => perp(a).compareTo(perp(b)));
    final rows = <List<_Box>>[];
    for (final b in boxes) {
      if (rows.isNotEmpty) {
        final ref = rows.last.first;
        if ((perp(b) - perp(ref)).abs() < 0.5 * math.min(b.h, ref.h)) {
          rows.last.add(b);
          b.row = rows.length - 1;
          continue;
        }
      }
      rows.add([b]);
      b.row = rows.length - 1;
    }
    return [
      for (final r in rows)
        ...(r..sort((a, b) => along(a).compareTo(along(b)))),
    ];
  }

  // ------------------------------------------------------------ recognition

  /// Warps the rotated box into a [_recHeight] high RGB patch.
  _Crop _crop(Uint8List rgb, int iw, int ih, _Box box) {
    final ratio = box.w / box.h;
    final outW = math.min(
      _maxRecWidth,
      math.max(16, (_recHeight * ratio).round()),
    );
    final out = Float32List(3 * _recHeight * outW);
    final ux = math.cos(box.angle), uy = math.sin(box.angle);
    for (var y = 0; y < _recHeight; y++) {
      final v = ((y + 0.5) / _recHeight - 0.5) * box.h;
      for (var x = 0; x < outW; x++) {
        final u = ((x + 0.5) / outW - 0.5) * box.w;
        final px = box.cx + u * ux - v * uy - 0.5;
        final py = box.cy + u * uy + v * ux - 0.5;
        final c = _sample(rgb, iw, ih, px, py);
        final o = y * outW + x;
        // B, G, R planes, (x/255 - 0.5) / 0.5.
        out[o] = c[2] / 127.5 - 1;
        out[_recHeight * outW + o] = c[1] / 127.5 - 1;
        out[2 * _recHeight * outW + o] = c[0] / 127.5 - 1;
      }
    }
    return _Crop(out, outW);
  }

  Future<(String, double)> _recognizeCrop(
    OrtSession session,
    List<String> dict,
    _Crop crop,
  ) async {
    final tensor = await OrtValue.fromList(crop.data, [
      1,
      3,
      _recHeight,
      crop.width,
    ]);
    final out = await session.run({session.inputNames.first: tensor});
    final result = out[session.outputNames.first]!;
    final shape = result.shape; // [1, T, C]
    final flat = await result.asFlattenedList();
    await tensor.dispose();
    await result.dispose();
    final steps = shape[1], classes = shape[2];
    final buffer = StringBuffer();
    var last = 0;
    var confSum = 0.0, confCount = 0;
    for (var t = 0; t < steps; t++) {
      var best = 0;
      var bestP = -1.0;
      final base = t * classes;
      for (var c = 0; c < classes; c++) {
        final p = (flat[base + c] as num).toDouble();
        if (p > bestP) {
          bestP = p;
          best = c;
        }
      }
      if (best != 0 && best != last) {
        if (best < dict.length) buffer.write(dict[best]);
        confSum += bestP;
        confCount++;
      }
      last = best;
    }
    return (buffer.toString(), confCount == 0 ? 0.0 : confSum / confCount);
  }

  List<_TextLine> _toLines(List<_Item> items) {
    final lines = <_TextLine>[];
    List<_Item>? row;
    for (final item in items) {
      if (row != null && item.box.row == row.first.box.row) {
        row.add(item);
      } else {
        row = [item];
        lines.add(_TextLine(row));
      }
    }
    return lines;
  }

  @override
  Future<void> dispose() async {}

  // ---------------------------------------------------------------- helpers

  static List<double> _sample(Uint8List rgb, int w, int h, double x, double y) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    int cl(int v, int hi) => v < 0 ? 0 : (v > hi ? hi : v);
    final xa = cl(x0, w - 1), xb = cl(x0 + 1, w - 1);
    final ya = cl(y0, h - 1), yb = cl(y0 + 1, h - 1);
    final out = [0.0, 0.0, 0.0];
    for (var c = 0; c < 3; c++) {
      final v00 = rgb[(ya * w + xa) * 3 + c];
      final v10 = rgb[(ya * w + xb) * 3 + c];
      final v01 = rgb[(yb * w + xa) * 3 + c];
      final v11 = rgb[(yb * w + xb) * 3 + c];
      out[c] =
          (v00 * (1 - fx) + v10 * fx) * (1 - fy) +
          (v01 * (1 - fx) + v11 * fx) * fy;
    }
    return out;
  }
}

class _Box {
  _Box(this.cx, this.cy, this.w, this.h, this.angle);
  final double cx, cy, w, h, angle;

  /// Reading row, set by `_sortBoxes`.
  int row = -1;

  _Box scaled(double sx, double sy) {
    // Anisotropic scale on a rotated box: keep it simple, the two factors are
    // equal in practice (both are the same resize ratio up to rounding).
    final s = (sx + sy) / 2;
    return _Box(cx * sx, cy * sy, w * s, h * s, angle);
  }

  Rect get bounds {
    final c = math.cos(angle).abs(), s = math.sin(angle).abs();
    final bw = w * c + h * s, bh = w * s + h * c;
    return Rect.fromCenter(center: Offset(cx, cy), width: bw, height: bh);
  }
}

class _Crop {
  _Crop(this.data, this.width);
  final Float32List data;
  final int width;
}

class _Item {
  _Item(this.box, this.text, this.conf);
  final _Box box;
  final String text;
  final double conf;
}

class _TextLine {
  _TextLine(this.items);
  final List<_Item> items;
  String get text => items.map((i) => i.text).join(' ');
}
