/// Invented documents for the image spike. Every name, number, code and
/// address is made up (`example.com`); no real document is ever used. The IBAN
/// and the RF code have the right shape but belong to nobody.
class SynthDocument {
  const SynthDocument({
    required this.name,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.lines,
    required this.keyTokens,
    this.pairs,
  });

  final String name;

  /// Size of the flat page in pixels (the aspect ratio is the paper's).
  final int width;
  final int height;
  final double fontSize;
  final List<String> lines;

  /// Words and numbers that must survive the OCR (used for recall).
  final List<String> keyTokens;

  /// For a table layout: the label (drawn at the left) and the value (drawn at
  /// the right margin) of each line, far apart. [lines] then holds the
  /// "label value" text of each line.
  final List<(String, String)>? pairs;
}

const receiptEl = SynthDocument(
  name: 'receipt_el',
  width: 700,
  height: 1500,
  fontSize: 34,
  lines: [
    'ΜΙΝΙ ΜΑΡΚΕΤ ΔΕΙΓΜΑ ΕΠΕ',
    'Οδός Δοκιμής 21, Πάτρα',
    'ΑΦΜ 987654321',
    'Απόδειξη 004517',
    'Ημ/νία 05/09/2026',
    'Γάλα φρέσκο 1L      1,39',
    'Ψωμί τοστ           1,85',
    'Τυρί φέτα 400γρ     4,70',
    'Ελιές Καλαμών       3,20',
    'Καφές ελληνικός     5,60',
    'ΣΥΝΟΛΟ 16,74 EUR',
    'Μετρητά 20,00',
    'Ρέστα 3,26',
    'Ευχαριστούμε!',
    'info@example.com',
  ],
  keyTokens: [
    'ΔΕΙΓΜΑ',
    'Πάτρα',
    '987654321',
    '004517',
    '05/09/2026',
    'Γάλα',
    'Ψωμί',
    'φέτα',
    'Καλαμών',
    '16,74',
    'EUR',
    '3,26',
    'info@example.com',
  ],
);

const receiptEn = SynthDocument(
  name: 'receipt_en',
  width: 700,
  height: 1400,
  fontSize: 34,
  lines: [
    'SAMPLE CORNER SHOP LTD',
    '12 Example Street',
    'VAT 55512345',
    'Receipt 220981',
    'Date 18/10/2026',
    'Bread loaf          2.10',
    'Orange juice 1L     3.45',
    'Cheddar 250g        4.99',
    'Tomatoes 1kg        2.80',
    'TOTAL 13.34 EUR',
    'Card ending 4242',
    'Thank you for shopping',
    'shop@example.com',
  ],
  keyTokens: [
    'SAMPLE',
    'Example',
    '55512345',
    '220981',
    '18/10/2026',
    'Bread',
    'Cheddar',
    'Tomatoes',
    '13.34',
    'EUR',
    '4242',
    'shop@example.com',
  ],
);

const billEl = SynthDocument(
  name: 'bill_el',
  width: 1240,
  height: 1754,
  fontSize: 34,
  lines: [
    'ΛΟΓΑΡΙΑΣΜΟΣ ΥΔΡΕΥΣΗΣ',
    'Εταιρεία Ύδρευσης Παράδειγμα ΔΕΥΑ',
    'Πελάτης: Ονοματεπώνυμο Δοκιμής',
    'Αριθμός παροχής 00123456',
    'Περίοδος 01/07/2026 - 30/09/2026',
    'Κατανάλωση 42 m3',
    'Πάγιο 6,40 €',
    'Χρέωση κατανάλωσης 31,25 €',
    'ΦΠΑ 13% 4,88 €',
    'Πληρωτέο ποσό 87,35 €',
    'Ημερομηνία λήξης 15/10/2026',
    'Κωδικός πληρωμής RF18 1234 5678 9012 3456 7890',
    'IBAN GR16 0110 1250 0000 0001 2300 695',
    'Αριθμός λογαριασμού 2026-778431',
    'Επικοινωνία: billing@example.com',
  ],
  keyTokens: [
    'ΥΔΡΕΥΣΗΣ',
    'Παράδειγμα',
    '00123456',
    '01/07/2026',
    '42',
    '6,40',
    '31,25',
    '4,88',
    '87,35',
    '15/10/2026',
    'RF18',
    '1234',
    '5678',
    '9012',
    '3456',
    '7890',
    'GR16',
    '0110',
    '1250',
    '2300',
    '695',
    '2026-778431',
    'billing@example.com',
  ],
);

const leafletEn = SynthDocument(
  name: 'leaflet_en',
  width: 1240,
  height: 1754,
  fontSize: 25,
  lines: [
    'EXAMPLE CITY LIBRARY: VISITOR GUIDE 2026',
    'Opening hours: Monday to Friday 09:00-20:00, Saturday 10:00-16:00.',
    'The reading room is on the second floor next to the periodicals desk.',
    'Membership is free for residents and costs 12.00 EUR a year otherwise.',
    'Each member may borrow up to eight books for a period of four weeks.',
    'Loans can be renewed twice online unless another reader has reserved',
    'the item. Late returns are charged 0.20 EUR per item for each day.',
    'Quiet study rooms can be booked for up to two hours at a time through',
    'the desk or by writing to rooms@example.com. Please bring your card.',
    'Children under twelve must be accompanied by an adult at all times.',
    'The children section offers story hours every Wednesday at 17:30.',
    'Wireless internet is available throughout the building: the network',
    'name is Guest-Library and the access code is printed on your receipt.',
    'Photocopying costs 0.10 EUR per page, colour printing 0.50 EUR.',
    'Lost cards should be reported at once; a replacement costs 3.00 EUR.',
    'Food is not allowed in the reading rooms, but drinks with a lid are',
    'welcome. Mobile phones must be silenced inside the building.',
    'Donations of books in good condition are accepted on Thursdays.',
    'The archive of local newspapers dates from 1871 and may be consulted',
    'by appointment, reference number ARC-4410, on weekday mornings.',
    'Guided tours of the historic reading hall start at 11:00 on the first',
    'Saturday of every month and last about forty minutes in total.',
    'Accessibility: a lift serves all floors and assistance dogs are welcome.',
    'Suggestions are collected in the box at the entrance each evening.',
    'Information line 555-0142, e-mail info@example.com, thank you.',
  ],
  keyTokens: [
    'EXAMPLE',
    '09:00-20:00',
    '12.00',
    'eight',
    '0.20',
    'rooms@example.com',
    'Guest-Library',
    '0.10',
    '0.50',
    '3.00',
    '1871',
    'ARC-4410',
    '11:00',
    '555-0142',
    'info@example.com',
  ],
);

const synthDocuments = [receiptEl, receiptEn, billEl, leafletEn];

/// A receipt in two columns (labels left, amounts at the right margin), like
/// the real receipt that showed a label paired with the wrong value on a
/// tilted page (Phase 2). Used only by the `tilted_table` scenes.
const receiptTableEl = SynthDocument(
  name: 'receipt_table_el',
  width: 800,
  height: 1500,
  fontSize: 34,
  lines: [
    'ΜΙΝΙ ΜΑΡΚΕΤ ΔΕΙΓΜΑ ΕΠΕ',
    'Γάλα φρέσκο 1L 1,39',
    'Ψωμί τοστ 1,85',
    'Τυρί φέτα 400γρ 4,70',
    'Ελιές Καλαμών 3,20',
    'Καφές ελληνικός 5,60',
    'Ελαιόλαδο 1L 12,40',
    'Μέλι θυμαρίσιο 9,25',
    'ΜΕΙΚΤΗ ΑΞΙΑ 38,39',
    'ΕΚΠΤΩΣΗ 0,00',
    'ΚΑΘΑΡΗ ΑΞΙΑ 38,39',
    'ΦΠΑ 13% 4,42',
    'ΣΥΝΟΛΟ 42,81',
    'ΜΕΤΡΗΤΑ 50,00',
    'ΡΕΣΤΑ 7,19',
  ],
  keyTokens: [
    'ΔΕΙΓΜΑ',
    'Γάλα',
    'Καλαμών',
    'ΜΕΙΚΤΗ',
    'ΕΚΠΤΩΣΗ',
    'ΚΑΘΑΡΗ',
    'ΣΥΝΟΛΟ',
    '42,81',
    '7,19',
  ],
  pairs: [
    ('Γάλα φρέσκο 1L', '1,39'),
    ('Ψωμί τοστ', '1,85'),
    ('Τυρί φέτα 400γρ', '4,70'),
    ('Ελιές Καλαμών', '3,20'),
    ('Καφές ελληνικός', '5,60'),
    ('Ελαιόλαδο 1L', '12,40'),
    ('Μέλι θυμαρίσιο', '9,25'),
    ('ΜΕΙΚΤΗ ΑΞΙΑ', '38,39'),
    ('ΕΚΠΤΩΣΗ', '0,00'),
    ('ΚΑΘΑΡΗ ΑΞΙΑ', '38,39'),
    ('ΦΠΑ 13%', '4,42'),
    ('ΣΥΝΟΛΟ', '42,81'),
    ('ΜΕΤΡΗΤΑ', '50,00'),
    ('ΡΕΣΤΑ', '7,19'),
  ],
);

/// Every document, including the ones the main dataset does not cycle through.
const allDocuments = [...synthDocuments, receiptTableEl];

SynthDocument documentByName(String name) =>
    allDocuments.firstWhere((d) => d.name == name);
