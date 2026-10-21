import 'app_strings.dart';

class AppStringsEl extends AppStrings {
  const AppStringsEl();

  @override
  String get appTitle => 'One Click Scan';

  @override
  String wizardStepIndicator(int current, int total) =>
      'Βήμα $current από $total';

  @override
  String get actionNext => 'Επόμενο';

  @override
  String get actionBack => 'Πίσω';

  @override
  String get actionFinish => 'Τέλος';

  @override
  String get welcomeTitle => 'Καλώς ήρθες';

  @override
  String get welcomeBody =>
      'Σάρωσε έγγραφα και στείλε τα με ένα πάτημα. Όλα γίνονται τοπικά στο '
      'κινητό σου. Δεν υπάρχει λογαριασμός ούτε cloud της εφαρμογής.';

  @override
  String get languageLabel => 'Γλώσσα εφαρμογής';

  @override
  String get folderTitle => 'Φάκελος αποθήκευσης';

  @override
  String get folderBody =>
      'Επίλεξε φάκελο όπου θα αποθηκεύονται τα έγγραφά σου. Έτσι έχεις '
      'άμεση πρόσβαση στα αρχεία σου και μπορείς εύκολα να τα μοιραστείς '
      'με άλλες εφαρμογές ή στο δικό σου cloud storage.';

  @override
  String get folderPick => 'Επιλογή φακέλου';

  @override
  String get folderChange => 'Αλλαγή φακέλου';

  @override
  String folderSelected(String name) => 'Επιλεγμένος φάκελος: $name';

  @override
  String get folderRequired => 'Επίλεξε φάκελο για να συνεχίσεις.';

  @override
  String get folderPickFailed =>
      'Δεν ήταν δυνατή η επιλογή φακέλου. Δοκίμασε ξανά.';

  @override
  String get mailTitle => 'Αποστολή με email';

  @override
  String get mailBody =>
      'Τα έγγραφα στέλνονται απευθείας από την εφαρμογή. Μπορείς να '
      'χρησιμοποιήσεις λογαριασμό διαφορετικό από αυτόν της συσκευής, ώστε '
      'να μη γεμίζει ο φάκελος «Απεσταλμένα» του κύριου email σου.';

  @override
  String get providerLabel => 'Πάροχος email';

  @override
  String get providerRequired => 'Επίλεξε πάροχο.';

  @override
  String get senderLabel => 'Λογαριασμός αποστολής (email)';

  @override
  String get destinationLabel => 'Παραλήπτης';

  @override
  String get destinationOwn => 'Στο δικό μου email';

  @override
  String get destinationCustom => 'Σε άλλο email';

  @override
  String get customDestinationLabel => 'Email παραλήπτη';

  @override
  String get invalidEmail => 'Μη έγκυρη διεύθυνση email.';

  @override
  String get galleryTitle => 'Αντίγραφα στη Gallery';

  @override
  String get galleryToggle => 'Αποθήκευση πρωτοτύπων στη Gallery';

  @override
  String get galleryNote =>
      'Αν ενεργοποιηθεί, οι φωτογραφίες των εγγράφων θα εμφανίζονται στη '
      'Gallery του κινητού. Εκεί τις βλέπουν άλλες εφαρμογές με πρόσβαση σε '
      'φωτογραφίες και μπορεί να αντιγραφούν σε υπηρεσίες cloud, αν έχεις '
      'ενεργό αυτόματο συγχρονισμό (π.χ. Google Photos). Αν τα έγγραφά σου '
      'έχουν ευαίσθητα δεδομένα, άφησέ το απενεργοποιημένο.';

  @override
  String get homeScanAndSend => 'ΣΑΡΩΣΗ & ΑΠΟΣΤΟΛΗ';

  @override
  String get homeComingSoon => 'Η κάμερα έρχεται στην επόμενη φάση.';

  @override
  String get homeFolderLabel => 'Φάκελος';

  @override
  String get homeRecipientLabel => 'Παραλήπτης';

  @override
  String get homeProviderLabel => 'Πάροχος';

  @override
  String get homeNotSet => 'Δεν έχει οριστεί';
}
