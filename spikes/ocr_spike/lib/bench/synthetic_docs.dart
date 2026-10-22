/// Synthetic documents. Every name, tax number and amount is invented
/// (`ΑΦΜ` values are not valid numbers, addresses are fictional).
library;

class Cell {
  const Cell(
    this.text,
    this.x, {
    this.right = false,
    this.bold = false,
    this.size,
    this.center = false,
  });

  final String text;

  /// Left edge, right edge when [right], middle when [center].
  final double x;
  final bool right;
  final bool center;
  final bool bold;
  final double? size;
}

class DocSpec {
  const DocSpec({
    required this.id,
    required this.type,
    required this.lang,
    required this.width,
    required this.font,
    required this.size,
    required this.rows,
    required this.keys,
    this.skipOrder = false,
  });

  final String id;

  /// receipt, bill, columns, mixed, spanish, russian
  final String type;

  /// el, es, ru (decides which Tesseract/Paddle language set is used)
  final String lang;
  final double width;
  final String font;
  final double size;

  /// Each row is drawn on its own line; null is an empty line.
  final List<List<Cell>?> rows;

  /// Key tokens: label -> value that must appear exactly.
  final Map<String, String> keys;

  /// Multi-column layouts have no single reading order: CER/WER are shown but
  /// the bag-of-words recall is the main number.
  final bool skipOrder;

  String get groundTruth => rows
      .where((r) => r != null)
      .map((r) => r!.map((c) => c.text).join(' '))
      .join('\n');
}

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

final List<DocSpec> syntheticDocs = [
  // ------------------------------------------------------------- receipts
  DocSpec(
    id: 'receipt_super1',
    type: 'receipt',
    lang: 'el',
    width: 800,
    font: 'NotoSansMono',
    size: 27,
    keys: {
      'store': 'ΜΑΡΚΕΤ ΔΕΙΓΜΑ Α.Ε.',
      'afm': '099999991',
      'date': '14/03/2026',
      'total': '38,72',
    },
    rows: [
      _c('ΜΑΡΚΕΤ ΔΕΙΓΜΑ Α.Ε.', 800, bold: true),
      _c('ΟΔΟΣ ΠΑΡΑΔΕΙΓΜΑΤΟΣ 12, 11111 ΑΘΗΝΑ', 800),
      _c('ΑΦΜ: 099999991  ΔΟΥ: ΔΕΙΓΜΑΤΟΣ', 800),
      _c('ΤΗΛ: 210 0000000', 800),
      null,
      _lr('ΗΜΕΡΟΜΗΝΙΑ: 14/03/2026', 'ΩΡΑ: 18:42', 800),
      _l('ΑΠΟΔΕΙΞΗ ΛΙΑΝΙΚΗΣ Νο 004512'),
      null,
      _lr('ΓΑΛΑ ΦΡΕΣΚΟ 1Λ', '1,85', 800),
      _lr('ΨΩΜΙ ΤΟΥ ΤΟΣΤ ΟΛΙΚΗΣ', '1,60', 800),
      _lr('ΤΥΡΙ ΦΕΤΑ ΠΟΠ 400Γ', '5,95', 800),
      _lr('ΜΗΛΑ ΡΕΝΕΤΕΣ 1,250 KG', '3,12', 800),
      _lr('ΕΛΑΙΟΛΑΔΟ ΕΞΤΡΑ ΠΑΡΘΕΝΟ 1Λ', '9,99', 800),
      _lr('ΜΑΚΑΡΟΝΙΑ ΝΟ6 500Γ', '1,20', 800),
      _lr('ΝΕΡΟ ΕΠΙΤΡΑΠΕΖΙΟ 6x1,5Λ', '2,70', 800),
      _lr('ΚΟΤΟΠΟΥΛΟ ΦΙΛΕΤΟ 0,780 KG', '8,31', 800),
      _lr('ΧΑΡΤΙ ΥΓΕΙΑΣ 4ΤΕΜ', '4,00', 800),
      null,
      _lr('ΣΥΝΟΛΟ', '38,72 €', 800, bold: true),
      _lr('ΜΕΤΡΗΤΑ', '40,00 €', 800),
      _lr('ΡΕΣΤΑ', '1,28 €', 800),
      _lr('ΦΠΑ 13%', '4,45 €', 800),
      null,
      _c('ΕΥΧΑΡΙΣΤΟΥΜΕ ΓΙΑ ΤΗΝ ΠΡΟΤΙΜΗΣΗ', 800),
    ],
  ),
  DocSpec(
    id: 'receipt_super2',
    type: 'receipt',
    lang: 'el',
    width: 760,
    font: 'NotoSans',
    size: 26,
    keys: {
      'store': 'ΤΡΙΑΝΤΑΦΥΛΛΟ ΜΙΝΙ ΜΑΡΚΕΤ',
      'afm': '099999992',
      'date': '02/11/2025',
      'total': '16,40',
    },
    rows: [
      _c('ΤΡΙΑΝΤΑΦΥΛΛΟ ΜΙΝΙ ΜΑΡΚΕΤ', 760, bold: true),
      _c('Λεωφ. Δοκιμών 5, Θεσσαλονίκη', 760),
      _c('ΑΦΜ 099999992 - ΔΟΥ Δείγματος', 760),
      null,
      _lr('Ημερομηνία 02/11/2025', '09:15', 760),
      _lr('Ταμίας 03', 'Απόδειξη 000871', 760),
      null,
      _lr('ΜΠΑΝΑΝΕΣ', '2,48', 760),
      _lr('ΓΙΑΟΥΡΤΙ ΣΤΡΑΓΓΙΣΤΟ 2x', '3,10', 760),
      _lr('ΑΥΓΑ ΜΕΣΑΙΑ 6ΤΕΜ', '2,35', 760),
      _lr('ΚΑΦΕΣ ΦΙΛΤΡΟΥ 250Γ', '5,49', 760),
      _lr('ΣΟΚΟΛΑΤΑ ΥΓΕΙΑΣ', '2,98', 760),
      null,
      _lr('ΣΥΝΟΛΟ ΠΛΗΡΩΤΕΟ', '16,40', 760, bold: true),
      _lr('ΚΑΡΤΑ', '16,40', 760),
      null,
      _c('Ευχαριστούμε! Καλή συνέχεια', 760),
    ],
  ),
  DocSpec(
    id: 'receipt_cafe',
    type: 'receipt',
    lang: 'el',
    width: 720,
    font: 'NotoSansMono',
    size: 26,
    keys: {
      'store': 'ΚΑΦΕ ΛΟΥΝΑ ΠΑΡΚ',
      'afm': '099999993',
      'date': '21/07/2026',
      'total': '9,60',
    },
    rows: [
      _c('ΚΑΦΕ ΛΟΥΝΑ ΠΑΡΚ', 720, bold: true),
      _c('ΠΛΑΤΕΙΑ ΔΕΙΓΜΑΤΟΣ 3', 720),
      _c('ΑΦΜ: 099999993', 720),
      null,
      _l('21/07/2026   11:07   ΤΡΑΠΕΖΙ 7'),
      null,
      _lr('1 ΕΣΠΡΕΣΟ ΔΙΠΛΟΣ', '3,20', 720),
      _lr('1 ΦΡΑΠΕ ΜΕΤΡΙΟΣ', '3,40', 720),
      _lr('1 ΤΟΣΤ ΓΑΛΟΠΟΥΛΑ', '3,00', 720),
      null,
      _lr('ΣΥΝΟΛΟ EUR', '9,60', 720, bold: true),
      _lr('ΜΕΤΡΗΤΑ', '10,00', 720),
      _lr('ΡΕΣΤΑ', '0,40', 720),
      null,
      _c('ΜΗ ΦΟΡΟΛΟΓΙΚΟ ΣΤΟΙΧΕΙΟ', 720),
    ],
  ),
  // ---------------------------------------------------------------- bills
  DocSpec(
    id: 'bill_energy1',
    type: 'bill',
    lang: 'el',
    width: 1654,
    font: 'NotoSans',
    size: 30,
    keys: {
      'store': 'ΔΕΙΓΜΑ ΕΝΕΡΓΕΙΑ Α.Ε.',
      'afm': '099999994',
      'date': '05/04/2026',
      'total': '84,36',
    },
    rows: [
      [
        const Cell('ΔΕΙΓΜΑ ΕΝΕΡΓΕΙΑ Α.Ε.', 80, bold: true, size: 44),
        const Cell('ΛΟΓΑΡΙΑΣΜΟΣ ΡΕΥΜΑΤΟΣ', 1574, right: true, bold: true),
      ],
      _l('Οδός Δοκιμών 1, 11111 Αθήνα · ΑΦΜ 099999994', 80),
      null,
      [
        const Cell('Αριθμός λογαριασμού:', 80),
        const Cell('7000000000123', 560),
        const Cell('Ημερομηνία έκδοσης:', 900),
        const Cell('05/04/2026', 1574, right: true),
      ],
      [
        const Cell('Περίοδος κατανάλωσης:', 80),
        const Cell('01/02/2026 - 31/03/2026', 560),
        const Cell('Ημερομηνία λήξης:', 900),
        const Cell('25/04/2026', 1574, right: true),
      ],
      null,
      [
        const Cell('ΠΕΡΙΓΡΑΦΗ', 80, bold: true),
        const Cell('ΠΟΣΟΤΗΤΑ', 900, right: true, bold: true),
        const Cell('ΤΙΜΗ', 1250, right: true, bold: true),
        const Cell('ΠΟΣΟ (€)', 1574, right: true, bold: true),
      ],
      [
        const Cell('Χρέωση προμήθειας ενέργειας', 80),
        const Cell('412 kWh', 900, right: true),
        const Cell('0,1520', 1250, right: true),
        const Cell('62,62', 1574, right: true),
      ],
      [
        const Cell('Πάγιο προμήθειας', 80),
        const Cell('2 μήνες', 900, right: true),
        const Cell('1,20', 1250, right: true),
        const Cell('2,40', 1574, right: true),
      ],
      [
        const Cell('Ρυθμιζόμενες χρεώσεις', 80),
        const Cell('412 kWh', 900, right: true),
        const Cell('0,0412', 1250, right: true),
        const Cell('16,97', 1574, right: true),
      ],
      [
        const Cell('Ειδικό τέλος μείωσης εκπομπών', 80),
        const Cell('412 kWh', 900, right: true),
        const Cell('0,0010', 1250, right: true),
        const Cell('0,41', 1574, right: true),
      ],
      [
        const Cell('Φόρος ΦΠΑ 6%', 80),
        const Cell('', 900, right: true),
        const Cell('', 1250, right: true),
        const Cell('1,96', 1574, right: true),
      ],
      null,
      [
        const Cell('Προηγούμενο υπόλοιπο', 80),
        const Cell('0,00', 1574, right: true),
      ],
      [
        const Cell('Έκπτωση συνέπειας', 80),
        const Cell('-0,00', 1574, right: true),
      ],
      [
        const Cell('ΣΥΝΟΛΙΚΟ ΠΟΣΟ ΠΛΗΡΩΜΗΣ', 80, bold: true, size: 36),
        const Cell('84,36 €', 1574, right: true, bold: true, size: 36),
      ],
      null,
      _l('Πληρωμή μέσω τραπέζης με κωδικό πληρωμής RF00 0000 0000 1234', 80),
      _l('Για πληροφορίες: 800 000 0000 (δωρεάν από σταθερό)', 80),
    ],
  ),
  DocSpec(
    id: 'bill_energy2',
    type: 'bill',
    lang: 'el',
    width: 1654,
    font: 'NotoSans',
    size: 30,
    keys: {
      'store': 'ΝΕΡΟ ΚΑΙ ΦΩΣ ΔΕΙΓΜΑΤΟΣ',
      'afm': '099999995',
      'date': '17/09/2025',
      'total': '127,05',
    },
    rows: [
      [
        const Cell('ΝΕΡΟ ΚΑΙ ΦΩΣ ΔΕΙΓΜΑΤΟΣ', 80, bold: true, size: 42),
        const Cell('ΛΟΓΑΡΙΑΣΜΟΣ ΥΠΗΡΕΣΙΩΝ', 1574, right: true, bold: true),
      ],
      _l('ΑΦΜ 099999995 · Τηλ. 210 0000000', 80),
      null,
      [
        const Cell('Ημερομηνία έκδοσης', 80),
        const Cell('17/09/2025', 700),
        const Cell('Τελευταία ημερομηνία πληρωμής', 900),
        const Cell('07/10/2025', 1574, right: true),
      ],
      null,
      [
        const Cell('Στοιχεία', 80, bold: true),
        const Cell('Ποσό (€)', 700, right: true, bold: true),
        const Cell('Στοιχεία', 900, bold: true),
        const Cell('Ποσό (€)', 1574, right: true, bold: true),
      ],
      [
        const Cell('Ύδρευση', 80),
        const Cell('48,20', 700, right: true),
        const Cell('Αποχέτευση', 900),
        const Cell('21,15', 1574, right: true),
      ],
      [
        const Cell('Πάγιο', 80),
        const Cell('6,50', 700, right: true),
        const Cell('Δημοτικά τέλη', 900),
        const Cell('32,40', 1574, right: true),
      ],
      [
        const Cell('Δημοτικός φόρος', 80),
        const Cell('4,80', 700, right: true),
        const Cell('Ειδικό τέλος', 900),
        const Cell('8,00', 1574, right: true),
      ],
      [
        const Cell('Τόκοι υπερημερίας', 80),
        const Cell('0,00', 700, right: true),
        const Cell('Προηγούμενο υπόλοιπο', 900),
        const Cell('6,00', 1574, right: true),
      ],
      null,
      [
        const Cell('ΣΥΝΟΛΙΚΟ ΠΟΣΟ ΠΛΗΡΩΜΗΣ', 80, bold: true, size: 36),
        const Cell('127,05 €', 1574, right: true, bold: true, size: 36),
      ],
      null,
      _l(
        'Η πληρωμή γίνεται σε όλα τα ΚΕΠ και στα καταστήματα συνεργαζόμενων τραπεζών.',
        80,
      ),
    ],
  ),
  // ------------------------------------------------------------ multi column
  DocSpec(
    id: 'columns1',
    type: 'columns',
    lang: 'el',
    width: 1654,
    font: 'NotoSans',
    size: 30,
    skipOrder: true,
    keys: {
      'store': 'ΕΝΗΜΕΡΩΤΙΚΟ ΔΕΛΤΙΟ',
      'afm': '099999996',
      'date': '30/06/2026',
      'total': '250,00',
    },
    rows: [
      _l('ΕΝΗΜΕΡΩΤΙΚΟ ΔΕΛΤΙΟ', 80, true),
      _l('Έκδοση 30/06/2026 · ΑΦΜ 099999996', 80),
      null,
      [
        const Cell('Νέα του συλλόγου', 80, bold: true),
        const Cell('Οικονομικά στοιχεία', 880, bold: true),
      ],
      [
        const Cell('Η ετήσια συνεδρίαση θα γίνει', 80),
        const Cell('Εισπράξεις έτους: 1.200,00', 880),
      ],
      [
        const Cell('την Παρασκευή στις 20:00 στην', 80),
        const Cell('Έξοδα έτους: 950,00', 880),
      ],
      [
        const Cell('αίθουσα εκδηλώσεων του δήμου.', 80),
        const Cell('Υπόλοιπο ταμείου: 250,00', 880),
      ],
      [
        const Cell('Παρακαλούμε να επιβεβαιώσετε', 80),
        const Cell('Η συνδρομή του νέου έτους', 880),
      ],
      [
        const Cell('τη συμμετοχή σας εγκαίρως.', 80),
        const Cell('παραμένει στα 20,00 ευρώ.', 880),
      ],
    ],
  ),
  // ----------------------------------------------------------------- mixed
  DocSpec(
    id: 'mixed1',
    type: 'mixed',
    lang: 'el',
    width: 1654,
    font: 'NotoSans',
    size: 30,
    keys: {
      'store': 'ΔΕΙΓΜΑ SOFTWARE ΕΠΕ',
      'afm': '099999997',
      'date': '12/12/2025',
      'total': '372,00',
    },
    rows: [
      [
        const Cell('ΔΕΙΓΜΑ SOFTWARE ΕΠΕ', 80, bold: true, size: 40),
        const Cell('Τιμολόγιο / Invoice', 1574, right: true, bold: true),
      ],
      _l('ΑΦΜ / VAT: 099999997 · www.example.com · billing@example.com', 80),
      null,
      [
        const Cell('Αριθμός / No:', 80),
        const Cell('INV-2025-0042', 500),
        const Cell('Ημερομηνία / Date:', 900),
        const Cell('12/12/2025', 1574, right: true),
      ],
      null,
      [
        const Cell('Περιγραφή / Description', 80, bold: true),
        const Cell('Τεμ. / Qty', 1000, right: true, bold: true),
        const Cell('Σύνολο / Total', 1574, right: true, bold: true),
      ],
      [
        const Cell('Άδεια χρήσης λογισμικού / Software license', 80),
        const Cell('1', 1000, right: true),
        const Cell('300,00', 1574, right: true),
      ],
      [
        const Cell('Υπηρεσίες υποστήριξης / Support services', 80),
        const Cell('2', 1000, right: true),
        const Cell('0,00', 1574, right: true),
      ],
      [
        const Cell('ΦΠΑ 24% / VAT 24%', 80),
        const Cell('', 1000, right: true),
        const Cell('72,00', 1574, right: true),
      ],
      null,
      [
        const Cell('Σύνολο προς πληρωμή / Total due', 80, bold: true, size: 34),
        const Cell('372,00 €', 1574, right: true, bold: true, size: 34),
      ],
      null,
      _l(
        'Πληρωμή με τραπεζική μεταφορά / Payment by bank transfer. IBAN: GR00 0000 0000 0000 0000 0000 000',
        80,
      ),
    ],
  ),
  DocSpec(
    id: 'mixed2',
    type: 'mixed',
    lang: 'el',
    width: 1654,
    font: 'NotoSans',
    size: 32,
    keys: {
      'store': 'ΣΧΟΛΗ ΞΕΝΩΝ ΓΛΩΣΣΩΝ',
      'afm': '099999998',
      'date': '08/10/2025',
      'total': '45,00',
    },
    rows: [
      _l('ΣΧΟΛΗ ΞΕΝΩΝ ΓΛΩΣΣΩΝ', 80, true),
      _l('ΑΦΜ 099999998 · 08/10/2025', 80),
      null,
      _l(
        'Η εγγραφή στο μάθημα Αγγλικών (level B2) και στο workshop Python έγινε.',
        80,
      ),
      _l(
        'Οι ώρες: Δευτέρα 17:30–19:00, Τετάρτη 18:00–19:30. Το κόστος είναι 45,00 €.',
        80,
      ),
      null,
      _l(
        'Μαθητής: Γιάννης Παπαδόπουλος · τάξη: Γ΄ Λυκείου · κωδικός: ΑΒ-1042',
        80,
      ),
      _l(
        'Είδος πληρωμής: μετρητά ή κάρτα. Πάχος φύλλου 25 µm, μέγεθος γραμμής μ.',
        80,
      ),
      null,
      _l('ΜΕ ΤΟΝΟΥΣ: ΆΛΦΑ ΈΝΑΣ ΉΧΟΣ ΊΣΩΣ ΌΛΑ ΎΨΟΣ ΏΡΑ ΪΣΩΣ ΫΨΟΣ', 80),
      _l('Χωρίς τόνους: ΑΛΦΑ ΕΝΑΣ ΗΧΟΣ ΙΣΩΣ ΟΛΑ ΥΨΟΣ ΩΡΑ.', 80),
      _l(
        'Πεζά: ά έ ή ί ό ύ ώ — λέξεις με τελικό ς: όλος, τέλος, ήλιος, γεωργός, μέσος.',
        80,
      ),
      _l(
        'Ο Μανόλης και η Ελένη αγόρασαν 3 βιβλία, 2 τετράδια και 1 USB stick.',
        80,
      ),
    ],
  ),
  // -------------------------------------------------------------- secondary
  DocSpec(
    id: 'spanish1',
    type: 'spanish',
    lang: 'es',
    width: 1654,
    font: 'NotoSans',
    size: 30,
    keys: {
      'store': 'FERRETERÍA EL MARTILLO',
      'afm': 'B99999999',
      'date': '09/05/2026',
      'total': '58,90',
    },
    rows: [
      [
        const Cell('FERRETERÍA EL MARTILLO', 80, bold: true, size: 40),
        const Cell('FACTURA', 1574, right: true, bold: true),
      ],
      _l('NIF: B99999999 · Calle de la Prueba 7, 28000 Madrid', 80),
      null,
      [
        const Cell('Fecha: 09/05/2026', 80),
        const Cell('Factura nº 2026-0318', 1574, right: true),
      ],
      null,
      [
        const Cell('Descripción', 80, bold: true),
        const Cell('Cantidad', 1000, right: true, bold: true),
        const Cell('Importe', 1574, right: true, bold: true),
      ],
      [
        const Cell('Tornillos de acero (caja)', 80),
        const Cell('3', 1000, right: true),
        const Cell('12,60', 1574, right: true),
      ],
      [
        const Cell('Pintura blanca 4 litros', 80),
        const Cell('1', 1000, right: true),
        const Cell('27,50', 1574, right: true),
      ],
      [
        const Cell('Pincel pequeño', 80),
        const Cell('2', 1000, right: true),
        const Cell('4,80', 1574, right: true),
      ],
      [
        const Cell('IVA 21%', 80),
        const Cell('', 1000, right: true),
        const Cell('10,00', 1574, right: true),
      ],
      null,
      [
        const Cell('TOTAL A PAGAR', 80, bold: true, size: 34),
        const Cell('58,90 €', 1574, right: true, bold: true, size: 34),
      ],
      null,
      _l(
        '¡Gracias por su compra! El año próximo habrá más ofertas, también para niños.',
        80,
      ),
    ],
  ),
  DocSpec(
    id: 'russian1',
    type: 'russian',
    lang: 'ru',
    width: 800,
    font: 'NotoSansMono',
    size: 27,
    keys: {
      'store': 'МАГАЗИН ОБРАЗЕЦ',
      'afm': '9999999999',
      'date': '15.08.2026',
      'total': '684,50',
    },
    rows: [
      _c('МАГАЗИН ОБРАЗЕЦ', 800, bold: true),
      _c('ул. Тестовая, д. 5, г. Пример', 800),
      _c('ИНН 9999999999', 800),
      null,
      _l('Чек № 0145      15.08.2026  14:20'),
      null,
      _lr('Хлеб белый', '45,00', 800),
      _lr('Молоко 3,2% 1 л', '89,90', 800),
      _lr('Сыр российский 300 г', '249,60', 800),
      _lr('Яблоки красные 1,5 кг', '300,00', 800),
      null,
      _lr('ИТОГО', '684,50', 800, bold: true),
      _lr('Наличными', '700,00', 800),
      _lr('Сдача', '15,50', 800),
      null,
      _c('Спасибо за покупку!', 800),
    ],
  ),
];
