import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'detection_postprocess.dart';
import 'detection_preprocess.dart';
import 'paddle_constants.dart';
import 'pixels.dart';
import 'recognition_preprocess.dart';
import 'text_box.dart';

/// One recognised character with its place along the text box, as fractions
/// 0..1 of the box length (left edge = 0). Derived from the CTC time step at
/// which the character was emitted.
class CharSpan {
  const CharSpan(this.ch, this.x0, this.x1);

  final String ch;
  final double x0, x1;
}

class SpikeLine {
  SpikeLine(this.text, this.confidence, this.box, this.chars, this.row);

  final String text;
  final double confidence;
  final TextBox box;
  final List<CharSpan> chars;
  final int row;
}

class SpikePage {
  SpikePage(this.width, this.height, this.lines, this.millis);

  final int width, height;
  final List<SpikeLine> lines;
  final int millis;
}

/// The OCR of the main app (copied and trimmed: root isolate, no cancel, no
/// SHA-256), plus the thing the PDF spike needs from it: where in the box each
/// character was emitted by CTC.
class SpikeOcr {
  SpikeOcr._(this._det, this._rec, this._dict);

  final OrtSession _det, _rec;
  final List<String> _dict;

  static Future<SpikeOcr> create(String pack) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/models',
    )..createSync(recursive: true);
    Future<String> extract(String name) async {
      final f = File('${dir.path}/$name');
      if (!f.existsSync()) {
        final data = await rootBundle.load('assets/models/$name');
        await f.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return f.path;
    }

    final ort = OnnxRuntime();
    final options = OrtSessionOptions(
      intraOpNumThreads: 4,
      providers: const [OrtProvider.CPU],
    );
    final det = await ort.createSession(
      await extract('det_mobile.onnx'),
      options: options,
    );
    final rec = await ort.createSession(
      await extract('rec_$pack.onnx'),
      options: options,
    );
    final text = await File(await extract('dict_$pack.txt')).readAsString();
    return SpikeOcr._(det, rec, parseDictionary(text));
  }

  Future<void> dispose() async {
    await _det.close();
    await _rec.close();
  }

  static List<String> parseDictionary(String text) {
    final chars = text.split('\n').map((l) => l.replaceAll('\r', '')).toList();
    if (chars.isNotEmpty && chars.last.isEmpty) chars.removeLast();
    return ['', ...chars, ' '];
  }

  /// [jpeg] is the upright working copy.
  Future<SpikePage> recognize(Uint8List jpeg, {int detSide = 960}) async {
    final sw = Stopwatch()..start();
    final px = await Isolate.run(() => _decode(jpeg));
    final (dw, dh) = detDims(px.w, px.h, detSide);
    final tensor = await OrtValue.fromList(detectionInput(px, dw, dh), [
      1,
      3,
      dh,
      dw,
    ]);
    final out = await _det.run({_det.inputNames.first: tensor});
    final map = out[_det.outputNames.first]!;
    final flat = await map.asFlattenedList();
    await tensor.dispose();
    await map.dispose();
    final prob = flat is Float32List ? flat : Float32List.fromList(flat.cast());
    final boxes = boxesFromMap(prob, dw, dh, px.w / dw, px.h / dh);

    final lines = <SpikeLine>[];
    for (final box in boxes) {
      final w = box.cropWidth;
      final data = Float32List(3 * PaddleConstants.recHeight * w);
      cropInto(px, box, data, 0, w);
      final rt = await OrtValue.fromList(data, [
        1,
        3,
        PaddleConstants.recHeight,
        w,
      ]);
      final ro = await _rec.run({_rec.inputNames.first: rt});
      final result = ro[_rec.outputNames.first]!;
      final steps = result.shape[1];
      final classes = result.shape[2];
      final rflat = await result.asFlattenedList();
      await result.dispose();
      await rt.dispose();
      final typed = rflat is Float32List
          ? rflat
          : Float32List.fromList(rflat.cast());
      final (text, conf, runs) = ctcWithSteps(typed, steps, classes, _dict);
      if (text.trim().isEmpty) continue;
      lines.add(SpikeLine(text, conf, box, charSpans(runs, steps), box.row));
    }
    return SpikePage(px.w, px.h, lines, sw.elapsedMilliseconds);
  }

  static Pixels _decode(Uint8List jpeg) {
    var image = img.decodeImage(jpeg)!;
    if (image.numChannels != 3) image = image.convert(numChannels: 3);
    return Pixels(
      image.getBytes(order: img.ChannelOrder.rgb),
      image.width,
      image.height,
      3,
    );
  }
}

/// One emitted character: its text and the first and last time step of its run.
typedef CtcRun = (String, int, int);

/// Greedy CTC like the main app's `ctcGreedy`, but also returns, per emitted
/// character, the time steps of its run (the position information the PDF
/// needs).
(String, double, List<CtcRun>) ctcWithSteps(
  Float32List flat,
  int steps,
  int classes,
  List<String> dict,
) {
  final buffer = StringBuffer();
  final runs = <CtcRun>[];
  var last = 0;
  var confSum = 0.0, confCount = 0;
  var runStart = 0;
  for (var s = 0; s < steps; s++) {
    var best = 0;
    final base = s * classes;
    var bestP = flat[base];
    for (var c = 1; c < classes; c++) {
      final p = flat[base + c];
      if (p > bestP) {
        bestP = p;
        best = c;
      }
    }
    if (best != 0 && best != last) {
      if (best < dict.length) {
        buffer.write(dict[best]);
        runs.add((dict[best], s, s));
        runStart = s;
      }
      confSum += bestP;
      confCount++;
    } else if (best != 0 && best == last && runs.isNotEmpty) {
      runs[runs.length - 1] = (runs.last.$1, runStart, s);
    }
    last = best;
  }
  return (buffer.toString(), confCount == 0 ? 0.0 : confSum / confCount, runs);
}

/// Turns runs into character extents (fractions of the box length). The
/// centre of a character is the middle of its run; the edges between two
/// characters are the midpoints of their centres.
List<CharSpan> charSpans(List<CtcRun> runs, int steps) {
  if (runs.isEmpty) return const [];
  final centres = [for (final r in runs) (r.$2 + r.$3 + 1) / 2 / steps];
  final spans = <CharSpan>[];
  for (var i = 0; i < runs.length; i++) {
    double left, right;
    if (centres.length == 1) {
      left = runs[i].$2 / steps;
      right = (runs[i].$3 + 1) / steps;
    } else {
      left = i == 0
          ? centres[0] - (centres[1] - centres[0]) / 2
          : (centres[i - 1] + centres[i]) / 2;
      right = i == centres.length - 1
          ? centres[i] + (centres[i] - centres[i - 1]) / 2
          : (centres[i] + centres[i + 1]) / 2;
    }
    spans.add(CharSpan(runs[i].$1, math.max(0.0, left), math.min(1.0, right)));
  }
  return spans;
}
