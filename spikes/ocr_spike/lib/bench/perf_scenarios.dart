import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'render.dart';
import 'synthetic_docs.dart';

/// Phase 1.6 timing scenarios. Everything is invented and generated at run
/// time from a fixed seed (no real data anywhere); the images are written to
/// the cache directory so the phone and the emulator run the same pixels.

/// `native` = as drawn (about 0.8 to 4 MP); `camera` = scaled up to about
/// 12 MP like a phone photo, which is what the JPEG decoder really sees in
/// Scan.
enum PhotoSize { native, camera }

class PerfScenario {
  const PerfScenario(this.id, this.label, this.spec, {this.poor = false});
  final String id;
  final String label;
  final DocSpec spec;

  /// Apply [degradePoor] after drawing.
  final bool poor;
}

const _words = [
  'παραγγελία',
  'τιμολόγιο',
  'ποσότητα',
  'προϊόν',
  'κατάστημα',
  'πελάτης',
  'ημερομηνία',
  'παράδοση',
  'διεύθυνση',
  'αριθμός',
  'σύνολο',
  'έκπτωση',
  'πληρωμή',
  'λογαριασμός',
  'κατανάλωση',
  'περίοδος',
  'υπηρεσία',
  'χρέωση',
  'εξυπηρέτηση',
  'σύμβαση',
  'ενέργεια',
  'τέλος',
  'φόρος',
  'ποσό',
  'στοιχεία',
  'αναλυτικά',
  'επιστροφή',
  'εγγύηση',
  'συσκευασία',
  'καταχώριση',
  'είδος',
  'κωδικός',
  'παρατηρήσεις',
  'πρόγραμμα',
  'ενημέρωση',
  'ισχύει',
  'μέχρι',
  'για',
  'και',
  'από',
  'στο',
  'της',
  'των',
  'με',
  'σε',
  'ως',
  'προς',
];

/// 3 columns x 17 lines of about 40 characters: roughly 2000 characters and
/// 51 text boxes, the shape of the page that took 5 s on the phone.
DocSpec _denseSpec() {
  final random = math.Random(7);
  const width = 1654.0, colW = 450.0, gutter = 95.0, left = 70.0;
  final rows = <List<Cell>?>[];
  final columns = <List<String>>[[], [], []];
  final keys = <String, String>{};
  for (var c = 0; c < 3; c++) {
    for (var r = 0; r < 17; r++) {
      final b = StringBuffer();
      while (b.length < 34) {
        if (b.isNotEmpty) b.write(' ');
        if (random.nextInt(9) == 0) {
          final amount =
              '${random.nextInt(900) + 10},${random.nextInt(90) + 10}';
          b.write(amount);
          if (keys.length < 6 && !keys.containsValue(amount)) {
            keys['amt${keys.length}'] = amount;
          }
        } else {
          b.write(_words[random.nextInt(_words.length)]);
        }
      }
      columns[c].add(b.toString());
    }
  }
  for (var r = 0; r < 17; r++) {
    rows.add([
      for (var c = 0; c < 3; c++)
        Cell(columns[c][r], left + c * (colW + gutter)),
    ]);
  }
  return DocSpec(
    id: 'perf_dense',
    type: 'columns',
    lang: 'el',
    width: width,
    font: 'NotoSans',
    size: 21,
    keys: keys,
    skipOrder: true,
    rows: rows,
  );
}

/// About 30 text lines, a supermarket-style slip.
DocSpec _receiptSpec() {
  final random = math.Random(11);
  const w = 800.0;
  const items = [
    'ΓΑΛΑ ΦΡΕΣΚΟ 1Λ',
    'ΨΩΜΙ ΤΟΣΤ ΟΛΙΚΗΣ',
    'ΤΥΡΙ ΦΕΤΑ 400Γ',
    'ΜΗΛΑ ΡΕΝΕΤΕΣ KG',
    'ΕΛΑΙΟΛΑΔΟ 1Λ',
    'ΜΑΚΑΡΟΝΙΑ 500Γ',
    'ΝΕΡΟ 6x1,5Λ',
    'ΚΟΤΟΠΟΥΛΟ ΦΙΛΕΤΟ KG',
    'ΧΑΡΤΙ ΥΓΕΙΑΣ 4ΤΕΜ',
    'ΓΙΑΟΥΡΤΙ ΣΤΡΑΓΓΙΣΤΟ',
    'ΑΥΓΑ ΜΕΓΑΛΑ 6ΤΕΜ',
    'ΝΤΟΜΑΤΕΣ KG',
    'ΑΓΓΟΥΡΙΑ KG',
    'ΚΑΦΕΣ ΦΙΛΤΡΟΥ 250Γ',
    'ΖΑΧΑΡΗ 1KG',
    'ΑΛΕΥΡΙ ΓΙΑ ΟΛΕΣ ΤΙΣ ΧΡΗΣΕΙΣ',
    'ΡΥΖΙ ΠΑΡΜΠΟΪΛΝΤ',
    'ΣΑΠΟΥΝΙ ΧΕΡΙΩΝ',
  ];
  var totalCents = 0;
  String money(int c) => '${c ~/ 100},${(c % 100).toString().padLeft(2, '0')}';
  final rows = <List<Cell>?>[
    [const Cell('ΜΑΡΚΕΤ ΔΕΙΓΜΑ Α.Ε.', w / 2, center: true, bold: true)],
    [const Cell('ΟΔΟΣ ΠΑΡΑΔΕΙΓΜΑΤΟΣ 12, 11111 ΑΘΗΝΑ', w / 2, center: true)],
    [const Cell('ΑΦΜ: 099999991  ΔΟΥ: ΔΕΙΓΜΑΤΟΣ', w / 2, center: true)],
    [const Cell('ΤΗΛ: 210 0000000', w / 2, center: true)],
    null,
    [
      const Cell('ΗΜΕΡΟΜΗΝΙΑ: 21/04/2026', 40),
      const Cell('ΩΡΑ: 19:05', w - 40, right: true),
    ],
    [const Cell('ΑΠΟΔΕΙΞΗ ΛΙΑΝΙΚΗΣ Νο 007731', 40)],
    null,
  ];
  for (var i = 0; i < 18; i++) {
    final cents = 50 + random.nextInt(1400);
    totalCents += cents;
    rows.add([Cell(items[i], 40), Cell(money(cents), w - 40, right: true)]);
  }
  final total = money(totalCents);
  rows.addAll([
    null,
    [
      const Cell('ΣΥΝΟΛΟ', 40, bold: true),
      Cell('$total €', w - 40, right: true, bold: true),
    ],
    [const Cell('ΚΑΡΤΑ', 40), Cell('$total €', w - 40, right: true)],
    null,
    [const Cell('ΕΥΧΑΡΙΣΤΟΥΜΕ ΓΙΑ ΤΗΝ ΠΡΟΤΙΜΗΣΗ', w / 2, center: true)],
  ]);
  return DocSpec(
    id: 'perf_receipt',
    type: 'receipt',
    lang: 'el',
    width: w,
    font: 'NotoSansMono',
    size: 27,
    keys: {
      'store': 'ΜΑΡΚΕΤ ΔΕΙΓΜΑ Α.Ε.',
      'afm': '099999991',
      'date': '21/04/2026',
      'total': total,
    },
    rows: rows,
  );
}

final List<PerfScenario> perfScenarios = [
  PerfScenario('receipt', 'Typical receipt (~30 lines)', _receiptSpec()),
  PerfScenario(
    'dense',
    'Dense page (3 columns, 51 lines, ~2000 chars)',
    _denseSpec(),
  ),
  PerfScenario(
    'poor',
    'Poor quality (blur, low contrast, tilt)',
    _receiptSpec(),
    poor: true,
  ),
];

/// Writes the JPEG of [scenario] at [size] into [dir] (re-used when present)
/// and returns it.
Future<File> buildScenarioImage(
  PerfScenario scenario,
  PhotoSize size,
  Directory dir,
) async {
  final file = File('${dir.path}/${scenario.id}_${size.name}_v1.jpg');
  if (file.existsSync()) return file;
  await dir.create(recursive: true);
  var image = await renderDoc(scenario.spec);
  if (scenario.poor) image = degradePoor(image, 5);
  if (size == PhotoSize.camera) {
    final scale = math.sqrt(12e6 / (image.width * image.height));
    if (scale > 1) {
      image = img.copyResize(
        image,
        width: (image.width * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }
  }
  await file.writeAsBytes(img.encodeJpg(image, quality: 88), flush: true);
  return file;
}
