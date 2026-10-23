import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../engines/paddle_engine.dart';
import 'perf_lab.dart';
import 'perf_study.dart';
import 'render.dart';
import 'synthetic_docs.dart';
import 'text_metrics.dart';

/// Phase 1.6c: do the Greek, Latin and East Slavic recognisers read English,
/// mixed Greek + English pages and accented Latin letters? Every name,
/// address, e-mail (`@example.com`) and number below is invented.

List<Cell> _l(String t, [double x = 40, bool bold = false]) => [
  Cell(t, x, bold: bold),
];
List<Cell> _c(String t, double w, {bool bold = false}) => [
  Cell(t, w / 2, center: true, bold: bold),
];
List<Cell> _lr(String a, String b, double w, {bool bold = false}) => [
  Cell(a, 40, bold: bold),
  Cell(b, w - 40, right: true, bold: bold),
];

/// Group of a document: `en`, `mix` (Greek and English) or `accents`.
class LangDoc {
  const LangDoc(this.group, this.spec);
  final String group;
  final DocSpec spec;
}

final List<LangDoc> langDocs = [
  LangDoc(
    'en',
    DocSpec(
      id: 'en_invoice',
      type: 'bill',
      lang: 'en',
      width: 900,
      font: 'NotoSans',
      size: 26,
      keys: {
        'invoice': 'INV-2026-0417',
        'email': 'billing@example.com',
        'date': '17 March 2026',
        'total': '1,284.50',
      },
      rows: [
        _c('NORTHFIELD SUPPLY LTD', 900, bold: true),
        _c('12 Sample Street, Exampleton EX1 2MP', 900),
        null,
        _lr('Invoice no. INV-2026-0417', 'Date: 17 March 2026', 900),
        _l('Customer: Harbour Lane Studio'),
        _l('Contact: billing@example.com'),
        null,
        _lr('Desk lamp, brushed steel (2)', '89.00', 900),
        _lr('Ergonomic chair, model C-440', '645.00', 900),
        _lr('Standing desk frame', '412.50', 900),
        _lr('Delivery and assembly', '138.00', 900),
        null,
        _lr('Total due (VAT included)', '1,284.50', 900, bold: true),
        _l('Payment within 30 days, thank you for your order.'),
      ],
    ),
  ),
  LangDoc(
    'en',
    DocSpec(
      id: 'en_letter',
      type: 'letter',
      lang: 'en',
      width: 900,
      font: 'NotoSans',
      size: 25,
      keys: {
        'reference': 'REF-88213',
        'email': 'support@example.com',
        'phone': '+44 20 7946 0000',
        'day': 'Tuesday 14 April',
      },
      rows: [
        _l('Dear customer,'),
        null,
        _l('Your appointment is confirmed for Tuesday 14 April at 10:30.'),
        _l('Please bring this letter and quote reference REF-88213.'),
        _l('If you need to change the date, write to support@example.com'),
        _l('or call +44 20 7946 0000 before noon on Monday.'),
        null,
        _l('Kind regards,'),
        _l('The Customer Service Team'),
      ],
    ),
  ),
  LangDoc(
    'mix',
    DocSpec(
      id: 'mix_shop',
      type: 'receipt',
      lang: 'el',
      width: 860,
      font: 'NotoSans',
      size: 26,
      keys: {
        'total': '31,40',
        'email': 'orders@example.com',
        'sku': 'M185',
        'date': '12/03/2026',
      },
      rows: [
        _c('ΗΛΕΚΤΡΟΝΙΚΑ ΔΕΙΓΜΑ Α.Ε.', 860, bold: true),
        _c('Οδός Παραδείγματος 7, Αθήνα', 860),
        _lr('Ημερομηνία: 12/03/2026', 'Order / Παραγγελία 5521', 860),
        null,
        _lr('USB-C Cable 1m', '12,90', 860),
        _lr('Wireless Mouse M185', '18,50', 860),
        _lr('Φορτιστής Fast Charge', '9,90', 860),
        _lr('Θήκη Laptop 15.6 inch', '14,90', 860),
        null,
        _lr('ΣΥΝΟΛΟ / TOTAL', '31,40 €', 860, bold: true),
        _l('Support: orders@example.com'),
        _l('Ευχαριστούμε / Thank you for your order'),
      ],
    ),
  ),
  LangDoc(
    'mix',
    DocSpec(
      id: 'mix_notice',
      type: 'letter',
      lang: 'el',
      width: 900,
      font: 'NotoSans',
      size: 25,
      keys: {
        'serial': 'AB12-CD34-EF56',
        'ssid': 'HOME-NET-5G',
        'url': 'www.example.com/help',
        'ref': 'ΑΡ. 2026-0098',
      },
      rows: [
        _l('Οδηγίες σύνδεσης του router (Wi-Fi) ΑΡ. 2026-0098'),
        _l('Δίκτυο: HOME-NET-5G, κωδικός πρόσβασης στην ετικέτα.'),
        _l('Σειριακός αριθμός (Serial Number): AB12-CD34-EF56'),
        _l('Πατήστε το κουμπί Reset για 10 δευτερόλεπτα.'),
        _l('Περισσότερες πληροφορίες: www.example.com/help'),
      ],
    ),
  ),
  LangDoc(
    'accents',
    DocSpec(
      id: 'acc_de',
      type: 'letter',
      lang: 'de',
      width: 900,
      font: 'NotoSans',
      size: 25,
      keys: {
        'city': 'München',
        'street': 'Straße',
        'word': 'Übergröße',
        'fee': 'Gebühr',
      },
      rows: [
        _l('Rechnung Nr. 2026-0042, Straße 12, 80331 München'),
        _l('Größe: 42, Übergröße auf Anfrage, Gebühr 12,50 €'),
        _l('Äpfel, Öl und Fußball für die Mädchen'),
        _l('Bitte prüfen Sie die Lieferung vor Öffnung.'),
      ],
    ),
  ),
  LangDoc(
    'accents',
    DocSpec(
      id: 'acc_fr',
      type: 'letter',
      lang: 'fr',
      width: 900,
      font: 'NotoSans',
      size: 25,
      keys: {
        'city': 'Besançon',
        'word': 'Réservation',
        'waiter': 'Garçon',
        'drink': 'crème',
      },
      rows: [
        _l('Facture n° 2026-117, Café crème 3,20 €'),
        _l('Réservation à Besançon, rue Saint-Honoré'),
        _l('Où êtes-vous? Garçon, l’addition, s’il vous plaît'),
        _l('Voilà un été très frais à Noël'),
      ],
    ),
  ),
  LangDoc(
    'accents',
    DocSpec(
      id: 'acc_es',
      type: 'letter',
      lang: 'es',
      width: 900,
      font: 'NotoSans',
      size: 25,
      keys: {
        'name': 'Muñoz',
        'word': 'señora',
        'year': 'Año',
        'open': '¿Dónde',
      },
      rows: [
        _l('¿Dónde está la señora Muñoz?'),
        _l('¡Gracias por su compra! Año 2026'),
        _l('Calle Mayor 5, Peñíscola, teléfono 960 000 000'),
        _l('Teléfono, canción, jamás, además'),
      ],
    ),
  ),
  LangDoc(
    'accents',
    DocSpec(
      id: 'acc_it',
      type: 'letter',
      lang: 'it',
      width: 900,
      font: 'NotoSans',
      size: 25,
      keys: {
        'word': 'Perché',
        'city': 'Città',
        'uni': 'università',
        'coffee': 'Caffè',
      },
      rows: [
        _l('Perché è già così? Città, università, qualità'),
        _l('Caffè 1,20 €, tè 2,00 €, più tardi però'),
        _l('Il papà è andato a Perugia'),
      ],
    ),
  ),
  LangDoc(
    'accents',
    DocSpec(
      id: 'acc_pt',
      type: 'letter',
      lang: 'pt',
      width: 900,
      font: 'NotoSans',
      size: 25,
      keys: {
        'word': 'Ação',
        'city': 'São Paulo',
        'heart': 'coração',
        'neg': 'não',
      },
      rows: [
        _l('Ação imediata, não é coração de pedra'),
        _l('Viagem a São Paulo, avenida Atlântica 100'),
        _l('Informação, também, você, avó'),
      ],
    ),
  ),
];

bool _accented(String c) {
  final u = c.runes.first;
  return (u >= 0xC0 && u <= 0x24F && u != 0xD7 && u != 0xF7) ||
      c == '¿' ||
      c == '¡';
}

class _Agg {
  int n = 0, keys = 0, keysTotal = 0, folded = 0;
  int accKept = 0, accTotal = 0;
  double cer = 0;
}

/// Greek, Latin and East Slavic recognisers on the invented English, mixed
/// and accented documents (4 conditions each). Prints numbers only.
Future<void> runLangPackBench({
  required PerfProgress progress,
  required LineSink out,
}) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/langbench');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  const conditions = [
    Condition.clean,
    Condition.rot3,
    Condition.blur,
    Condition.lowContrastNoise,
  ];
  final files = <(LangDoc, Condition), File>{};
  var seed = 100;
  for (final d in langDocs) {
    final clean = await renderDoc(d.spec);
    for (final c in conditions) {
      progress('G: render ${d.spec.id} ${c.label}');
      files[(d, c)] = await writeJpeg(
        dir,
        '${d.spec.id}__${c.label}',
        applyCondition(clean, c, seed++),
      );
    }
  }
  out('G: language packs on invented documents. ${await envLine()}');
  final agg = <String, _Agg>{};
  for (final model in ['greek', 'latin', 'eslav']) {
    await PaddleEngine.releaseAll();
    final engine = PerfExperiment(
      'lp_$model',
      'lp',
      model,
      studyConfig,
    ).build(model);
    try {
      await engine.prepare();
      for (final entry in files.entries) {
        final (d, c) = entry.key;
        progress('G: $model ${d.spec.id} ${c.label}');
        final r = await engine.recognize(entry.value.path);
        if (r.error != null) {
          out('G ERROR $model ${d.spec.id} ${c.label}: ${r.error}');
          continue;
        }
        final gt = d.spec.groundTruth;
        final s = score(gt, r.text);
        final a = agg.putIfAbsent('${d.group}|$model', _Agg.new);
        final b = agg.putIfAbsent('${d.spec.id}|$model', _Agg.new);
        final gtChars = chars(collapse(gt));
        final al = align(gtChars, chars(collapse(r.text)));
        for (final x in [a, b]) {
          x.n++;
          x.cer += s.cer;
          x.keysTotal += d.spec.keys.length;
          x.keys += d.spec.keys.values
              .where((v) => containsValue(r.text, v))
              .length;
          x.folded += d.spec.keys.values
              .where((v) => containsFolded(r.text, v))
              .length;
          for (var i = 0; i < gtChars.length; i++) {
            if (_accented(gtChars[i])) {
              x.accTotal++;
              if (al.matched[i]) x.accKept++;
            }
          }
        }
      }
    } finally {
      await engine.dispose();
    }
  }
  await PaddleEngine.releaseAll();
  String line(String name, _Agg x) =>
      '$name: n=${x.n} CER ${(100 * x.cer / x.n).toStringAsFixed(1)}% '
      'keys ${x.keys}/${x.keysTotal} (accent-blind ${x.folded}/${x.keysTotal})'
      '${x.accTotal == 0 ? '' : ' accented letters kept ${x.accKept}/${x.accTotal}'}';
  for (final group in ['en', 'mix', 'accents']) {
    for (final model in ['greek', 'latin', 'eslav']) {
      out(line('G $group, model $model', agg['$group|$model']!));
    }
  }
  for (final d in langDocs) {
    final parts = [
      for (final model in ['greek', 'latin', 'eslav'])
        '$model CER ${(100 * agg['${d.spec.id}|$model']!.cer / agg['${d.spec.id}|$model']!.n).toStringAsFixed(1)}% '
            'keys ${agg['${d.spec.id}|$model']!.keys}/${agg['${d.spec.id}|$model']!.keysTotal}',
    ];
    out('G ${d.spec.id}: ${parts.join(', ')}');
  }
}
