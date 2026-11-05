import 'dart:math' as math;

import 'documents.dart';
import 'scene.dart';

const datasetSeed = 20261030;

/// The fixed list of synthetic photos (the same list every time). Every
/// category from the request is there, plus hard negatives and combinations.
List<SceneSpec> buildDataset({int width = 1536, int height = 2048}) {
  final rng = math.Random(datasetSeed);
  final specs = <SceneSpec>[];
  var docCursor = 0;
  String nextDoc() => synthDocuments[docCursor++ % synthDocuments.length].name;

  void add(
    String category, {
    String? document,
    double tiltXDeg = 0,
    double tiltYDeg = 0,
    double rollDeg = 0,
    double fill = 0.8,
    double offsetX = 0,
    double offsetY = 0,
    Background background = Background.table,
    double lightGradient = 0.12,
    bool shadowBand = false,
    double contrast = 1.0,
    double crumple = 0,
    bool hand = false,
    double noise = 3,
    bool hasDocument = true,
  }) {
    final n = specs.length;
    specs.add(
      SceneSpec(
        id: '${category}_${n.toString().padLeft(2, '0')}',
        category: category,
        document: document ?? nextDoc(),
        seed: datasetSeed + 101 * n,
        width: width,
        height: height,
        tiltXDeg: tiltXDeg,
        tiltYDeg: tiltYDeg,
        rollDeg: rollDeg,
        fill: fill,
        offsetX: offsetX,
        offsetY: offsetY,
        background: background,
        lightGradient: lightGradient,
        shadowBand: shadowBand,
        contrast: contrast,
        crumple: crumple,
        hand: hand,
        noise: noise,
        hasDocument: hasDocument,
      ),
    );
  }

  double jitter(double range) => (rng.nextDouble() * 2 - 1) * range;

  for (var i = 0; i < 4; i++) {
    add('frontal', fill: 0.78 + jitter(0.05));
  }
  for (final deg in [10.0, 20.0, 30.0]) {
    for (var i = 0; i < 2; i++) {
      add(
        'perspective',
        tiltXDeg: i == 0 ? deg : jitter(5),
        tiltYDeg: i == 0 ? jitter(5) : deg * (rng.nextBool() ? 1 : -1),
        rollDeg: jitter(2),
        fill: 0.8,
      );
    }
  }
  for (final deg in [5.0, 10.0, 15.0]) {
    for (var i = 0; i < 2; i++) {
      add('rotation', rollDeg: i == 0 ? deg : -deg, fill: 0.74);
    }
  }
  for (var i = 0; i < 6; i++) {
    add(
      'light',
      lightGradient: 0.3 + jitter(0.1),
      shadowBand: i.isEven,
      rollDeg: jitter(4),
      tiltXDeg: jitter(8),
    );
  }
  for (var i = 0; i < 5; i++) {
    add('low_contrast', contrast: 0.42 + jitter(0.06), rollDeg: jitter(3));
  }
  for (var i = 0; i < 6; i++) {
    add(
      'crumple',
      crumple: 5 + rng.nextDouble() * 9,
      tiltXDeg: jitter(10),
      rollDeg: jitter(3),
    );
  }
  for (var i = 0; i < 6; i++) {
    add(
      'noisy_background',
      background: i.isEven ? Background.table : Background.clutter,
      rollDeg: jitter(8),
      tiltXDeg: jitter(10),
      noise: 6,
    );
  }
  for (var i = 0; i < 4; i++) {
    add('hand', hand: true, rollDeg: jitter(5), tiltXDeg: jitter(8));
  }
  for (var i = 0; i < 5; i++) {
    add(
      'dark_background',
      background: Background.dark,
      rollDeg: jitter(6),
      tiltYDeg: jitter(10),
    );
  }
  for (var i = 0; i < 5; i++) {
    final dx = (i.isEven ? 1 : -1) * (0.1 + rng.nextDouble() * 0.08);
    add(
      'partial',
      fill: 0.95,
      offsetX: i < 3 ? dx : 0,
      offsetY: i < 3 ? 0 : (i == 3 ? 0.12 : -0.12),
      rollDeg: jitter(4),
    );
  }
  for (var i = 0; i < 3; i++) {
    add('fills_frame', fill: 1.4 + jitter(0.05), rollDeg: jitter(2));
  }
  for (var i = 0; i < 5; i++) {
    add(
      'small_document',
      fill: 0.32 + jitter(0.06),
      offsetX: jitter(0.18),
      offsetY: jitter(0.2),
      rollDeg: jitter(10),
      tiltXDeg: jitter(10),
    );
  }
  for (var i = 0; i < 6; i++) {
    add(
      'lines_background',
      background: Background.lines,
      rollDeg: jitter(6),
      tiltXDeg: jitter(8),
      fill: 0.66 + jitter(0.1),
    );
  }
  for (var i = 0; i < 4; i++) {
    add(
      'no_document',
      background: i.isEven ? Background.lines : Background.clutter,
      hasDocument: false,
    );
  }
  for (var i = 0; i < 6; i++) {
    add(
      'combined',
      tiltXDeg: 12 + jitter(8),
      tiltYDeg: jitter(15),
      rollDeg: jitter(12),
      lightGradient: 0.3,
      shadowBand: true,
      crumple: 4 + rng.nextDouble() * 5,
      contrast: 0.65,
      background: i < 3 ? Background.clutter : Background.table,
      noise: 6,
      hand: i == 5,
      fill: 0.75 + jitter(0.06),
    );
  }
  // Tilted two-column receipts (reading-order and pairing check).
  for (final roll in [0.0, 5.0, 10.0, 15.0, -10.0, -15.0]) {
    add(
      'tilted_table',
      document: 'receipt_table_el',
      rollDeg: roll,
      fill: 0.78,
      tiltXDeg: jitter(4),
    );
  }
  return specs;
}
