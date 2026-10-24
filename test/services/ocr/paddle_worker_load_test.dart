import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack.dart';
import 'package:one_click_scan/services/ocr/ocr_model_store.dart';
import 'package:one_click_scan/services/ocr/paddle_worker.dart';

OcrModelFile describe(String name, List<int> bytes) => OcrModelFile(
  name: name,
  sha256: sha256.convert(bytes).toString(),
  bytes: bytes.length,
);

/// The verification the worker does before a model reaches ONNX Runtime. These
/// cases end before any plugin call, so they run on the host.
void main() {
  late Directory dir;
  final det = utf8.encode('detector');
  final rec = utf8.encode('recogniser');
  final dict = utf8.encode('a\nb\n');

  OcrModelPaths paths() => OcrModelPaths(
    packId: 'p',
    detPath: '${dir.path}/det.onnx',
    recPath: '${dir.path}/rec.onnx',
    dictPath: '${dir.path}/dict.txt',
    det: describe('det.onnx', det),
    rec: describe('rec.onnx', rec),
    dict: describe('dict.txt', dict),
  );

  void write(String name, List<int> bytes) =>
      File('${dir.path}/$name').writeAsBytesSync(bytes);

  setUp(() => dir = Directory.systemTemp.createTempSync('worker_load_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'a tampered model (same size, other bytes) is refused and named',
    () async {
      write('det.onnx', det);
      write('rec.onnx', [...rec]..[0] ^= 0xFF);
      write('dict.txt', dict);
      final messages = <String>[];

      final result = await PaddleWorker().load(
        paths(),
        (stage, done, total) => messages.add(stage),
      );

      expect(result['status'], 'failed');
      expect(result['reason'], WorkerFailure.modelUnavailable);
      expect(result['bad'], ['rec.onnx']);
      expect(messages, ['loadingModels']);
    },
  );

  test('a missing file is refused', () async {
    write('det.onnx', det);
    write('dict.txt', dict);

    final result = await PaddleWorker().load(paths(), (_, _, _) {});

    expect(result['reason'], WorkerFailure.modelUnavailable);
    expect(result['bad'], ['rec.onnx']);
  });

  test('a truncated dictionary is refused too', () async {
    write('det.onnx', det);
    write('rec.onnx', rec);
    write('dict.txt', dict.sublist(0, 2));

    final result = await PaddleWorker().load(paths(), (_, _, _) {});

    expect(result['bad'], ['dict.txt']);
  });

  test('every bad file is listed', () async {
    final result = await PaddleWorker().load(paths(), (_, _, _) {});

    expect(result['bad'], ['det.onnx', 'rec.onnx', 'dict.txt']);
  });
}
