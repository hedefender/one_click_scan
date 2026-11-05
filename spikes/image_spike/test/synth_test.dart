import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_spike/src/synth/dataset.dart';
import 'package:image_spike/src/synth/documents.dart';
import 'package:image_spike/src/synth/scene.dart';

/// A plain flat page (white with one dark bar) so the tests need no fonts.
FlatPage plainPage() {
  const w = 300, h = 420;
  final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 240);
  for (var y = 40; y < 60; y++) {
    for (var x = 30; x < 270; x++) {
      final o = (y * w + x) * 3;
      rgb[o] = rgb[o + 1] = rgb[o + 2] = 20;
    }
  }
  return FlatPage(w, h, rgb);
}

void main() {
  final page = plainPage();

  test('the dataset has several dozen scenes, unique ids, fixed content', () {
    final a = buildDataset();
    final b = buildDataset();
    expect(a.length, inInclusiveRange(60, 100));
    expect(a.map((s) => s.id).toSet().length, a.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].id, b[i].id);
      expect(a[i].seed, b[i].seed);
      expect(a[i].tiltXDeg, b[i].tiltXDeg);
    }
    final categories = a.map((s) => s.category).toSet();
    for (final c in [
      'frontal',
      'perspective',
      'rotation',
      'light',
      'low_contrast',
      'crumple',
      'noisy_background',
      'hand',
      'dark_background',
      'partial',
      'fills_frame',
      'small_document',
      'lines_background',
      'no_document',
      'combined',
    ]) {
      expect(categories, contains(c));
    }
    for (final s in a) {
      expect(allDocuments.map((d) => d.name), contains(s.document));
    }
  });

  test('the same spec draws the same picture', () {
    const spec = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 7,
      width: 300,
      height: 400,
      tiltXDeg: 15,
      rollDeg: 5,
      crumple: 4,
      hand: true,
    );
    final a = renderScene(spec, page);
    final b = renderScene(spec, page);
    expect(a.image.getBytes(), b.image.getBytes());
    expect(a.truth!.p[0].x, b.truth!.p[0].x);
  });

  test('the truth outline of a frontal page is a centred rectangle', () {
    const spec = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 1,
      width: 600,
      height: 800,
      fill: 0.8,
    );
    final r = renderScene(spec, page);
    final q = r.truth!;
    expect(r.partial, isFalse);
    expect(r.fillsFrame, isFalse);
    expect(q.isConvex, isTrue);
    for (final a in q.anglesDeg) {
      expect(a, closeTo(90, 0.01));
    }
    // The page ratio is kept (300 x 420) and it fits the frame.
    expect(q.topWidth / q.leftHeight, closeTo(300 / 420, 0.001));
    final cx = q.p.map((p) => p.x).reduce((a, b) => a + b) / 4;
    expect(cx, closeTo(300, 0.5));
  });

  test('a tilted page keeps a convex outline and loses its right angles', () {
    const spec = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 1,
      width: 600,
      height: 800,
      tiltYDeg: 30,
    );
    final q = renderScene(spec, page).truth!;
    expect(q.isConvex, isTrue);
    expect((q.leftHeight - q.rightHeight).abs(), greaterThan(5));
  });

  test('rotation turns the outline by the roll angle', () {
    const spec = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 1,
      width: 600,
      height: 800,
      rollDeg: 10,
    );
    final q = renderScene(spec, page).truth!;
    final dx = q.p[1].x - q.p[0].x, dy = q.p[1].y - q.p[0].y;
    expect(dy / dx, closeTo(0.17633, 0.002)); // tan 10 degrees
  });

  test('partial and fills-frame are reported', () {
    const partial = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 1,
      width: 600,
      height: 800,
      fill: 0.95,
      offsetX: 0.2,
    );
    final p = renderScene(partial, page);
    expect(p.partial, isTrue);
    expect(p.fillsFrame, isFalse);

    const full = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 1,
      width: 600,
      height: 800,
      fill: 1.6,
    );
    final f = renderScene(full, page);
    expect(f.fillsFrame, isTrue);
    expect(f.partial, isFalse);
    expect(f.truth!.area, closeTo(600 * 800, 1));
  });

  test('a scene without a document has no truth', () {
    const spec = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 1,
      width: 300,
      height: 400,
      hasDocument: false,
      background: Background.lines,
    );
    final r = renderScene(spec, page);
    expect(r.truth, isNull);
    expect(r.image.width, 300);
  });

  test('the page is really drawn inside its outline, the table outside', () {
    const spec = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 3,
      width: 600,
      height: 800,
      fill: 0.7,
      noise: 0,
      lightGradient: 0,
      background: Background.dark,
    );
    final r = renderScene(spec, page);
    final q = r.truth!;
    final cx = ((q.p[0].x + q.p[2].x) / 2).round();
    final cy = ((q.p[0].y + q.p[2].y) / 2).round();
    // Page centre is the pale paper; a frame corner is the dark table.
    expect(r.image.getPixel(cx, cy).r.toInt(), greaterThan(180));
    expect(r.image.getPixel(2, 2).r.toInt(), lessThan(80));
  });

  test('every dataset spec is a valid projection (convex outline)', () {
    for (final s in buildDataset()) {
      if (!s.hasDocument) continue;
      final doc = documentByName(s.document);
      expect(
        projectPage(s, doc.width, doc.height).isConvex,
        isTrue,
        reason: s.id,
      );
    }
  });

  test('key tokens appear in the lines of each document', () {
    for (final d in allDocuments) {
      final text = d.lines.join(' ');
      for (final t in d.keyTokens) {
        expect(text, contains(t), reason: '${d.name}: $t');
      }
    }
  });
}
