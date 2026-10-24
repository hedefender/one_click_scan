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
      'Όταν είναι ενεργό, εμφανίζεται αντίγραφο των φωτογραφιών στη Gallery '
      'του κινητού. Εκεί το βλέπουν άλλες εφαρμογές με πρόσβαση σε '
      'φωτογραφίες και μπορεί να αντιγραφεί σε υπηρεσίες cloud, αν έχεις '
      'ενεργό αυτόματο συγχρονισμό (π.χ. Google Photos). Όταν είναι '
      'ανενεργό, οι φωτογραφίες μένουν μόνο στον φάκελο που διάλεξες και δεν '
      'εμφανίζονται στη Gallery. Αν τα έγγραφά σου έχουν ευαίσθητα δεδομένα, '
      'άφησέ το απενεργοποιημένο.';

  @override
  String get homeScanAndSend => 'ΣΑΡΩΣΗ & ΑΠΟΣΤΟΛΗ';

  @override
  String get scanModeSingle => 'Μία σελίδα';

  @override
  String get scanModeMulti => 'Πολλές σελίδες';

  @override
  String get scanCaptureButton => 'Λήψη';

  @override
  String get scanDone => 'Τέλος';

  @override
  String get scanDeleteLast => 'Διαγραφή τελευταίας σελίδας';

  @override
  String scanPageCount(int count) => 'Σελίδες: $count';

  @override
  String get scanSaving => 'Αποθήκευση...';

  @override
  String get scanRetry => 'Δοκίμασε ξανά';

  @override
  String get scanPermissionDenied =>
      'Χρειάζεται πρόσβαση στην κάμερα για να σαρώσεις έγγραφα. Επίτρεψέ την για να συνεχίσεις.';

  @override
  String get scanOpenAppSettings => 'Ρυθμίσεις εφαρμογής';

  @override
  String get scanCameraUnavailable =>
      'Η κάμερα δεν είναι διαθέσιμη σε αυτή τη συσκευή.';

  @override
  String get scanCaptureFailed => 'Η φωτογραφία δεν τραβήχτηκε. Δοκίμασε ξανά.';

  @override
  String get scanSaveFailed =>
      'Οι σελίδες δεν αποθηκεύτηκαν στον φάκελό σου. Έχουν κρατηθεί, οπότε '
      'μπορείς να δοκιμάσεις ξανά.';

  @override
  String get scanDiscardTitle => 'Να απορριφθεί η σάρωση;';

  @override
  String get scanDiscardBody => 'Οι σελίδες που τράβηξες θα διαγραφούν.';

  @override
  String get scanResultTitle => 'Η σάρωση αποθηκεύτηκε';

  @override
  String scanResultSummary(int count, String folderName) => count == 1
      ? 'Αποθηκεύτηκε 1 αρχείο στο "$folderName/pictures"'
      : 'Αποθηκεύτηκαν $count αρχεία στο "$folderName/pictures"';

  @override
  String get scanGallerySaved => 'Αντίγραφο αποθηκεύτηκε στη Gallery';

  @override
  String get scanGalleryFailed => 'Το αντίγραφο στη Gallery απέτυχε';

  @override
  String get scanBackHome => 'Επιστροφή στην αρχική';

  @override
  String get homeFolderLabel => 'Φάκελος';

  @override
  String get homeRecipientLabel => 'Παραλήπτης';

  @override
  String get homeProviderLabel => 'Πάροχος';

  @override
  String get homeNotSet => 'Δεν έχει οριστεί';

  @override
  String get homeFolderLostBanner => 'Ο φάκελος δεν είναι πλέον προσβάσιμος';

  @override
  String get homeOpenSettings => 'Ρυθμίσεις';

  @override
  String get settingsTitle => 'Ρυθμίσεις';

  @override
  String get settingsSaveButton => 'Αποθήκευση';

  @override
  String get settingsSaved => 'Οι ρυθμίσεις αποθηκεύτηκαν.';

  @override
  String get settingsFolderAccessLost =>
      'Η εφαρμογή δεν έχει πλέον πρόσβαση σε αυτόν τον φάκελο. Επίλεξε ξανά φάκελο.';

  @override
  String get settingsUnsavedTitle => 'Μη αποθηκευμένες αλλαγές';

  @override
  String get settingsUnsavedBody =>
      'Έχεις αλλαγές στις ρυθμίσεις email που δεν έχουν αποθηκευτεί.';

  @override
  String get settingsDiscard => 'Απόρριψη';

  @override
  String get settingsStay => 'Μείνε';

  @override
  String get ocrOpenResult => 'Κείμενο OCR (έλεγχος)';

  @override
  String get ocrResultTitle => 'Κείμενο OCR';

  @override
  String ocrPageOf(int page, int total) => 'Σελίδα $page από $total';

  @override
  String get ocrStatusQueued => 'Αναμονή για την προηγούμενη σελίδα';

  @override
  String get ocrStatusLoadingModels => 'Φόρτωση των γλωσσικών μοντέλων';

  @override
  String get ocrStatusPreparing => 'Προετοιμασία της εικόνας';

  @override
  String get ocrStatusDetecting => 'Αναζήτηση κειμένου';

  @override
  String ocrStatusRecognizing(int done, int total) =>
      total == 0 ? 'Ανάγνωση κειμένου' : 'Ανάγνωση γραμμής $done από $total';

  @override
  String ocrSummaryPack(String name) => 'Πακέτο γλώσσας: $name';

  @override
  String ocrSummaryDuration(String seconds) => 'Χρόνος: $seconds s';

  @override
  String ocrSummaryWorkImage(int width, int height) =>
      'Εικόνα εργασίας: $width x $height px';

  @override
  String ocrSummaryCapture(int width, int height, String megapixels) =>
      'Λήψη: $width x $height px ($megapixels MP)';

  @override
  String ocrSummaryBoxes(int boxes, int filtered) =>
      'Κουτιά: $boxes (φιλτραρισμένα: $filtered)';

  @override
  String ocrSummaryBorderline(int count) =>
      'Οριακές γραμμές (0,50 έως 0,65): $count';

  @override
  String get ocrFilteredLabel => 'φιλτραρισμένη, χαμηλή βεβαιότητα';

  @override
  String get ocrNoText => 'Δεν βρέθηκε κείμενο σε αυτή τη σελίδα.';

  @override
  String get ocrCopy => 'Αντιγραφή κειμένου';

  @override
  String get ocrCopied => 'Το κείμενο αντιγράφηκε.';

  @override
  String get ocrShowBoxes => 'Εμφάνιση κουτιών πάνω στην εικόνα';

  @override
  String get ocrTimedOut =>
      'Η ανάγνωση της σελίδας κράτησε πολύ και σταμάτησε.';

  @override
  String get ocrCancelled => 'Η ανάγνωση ακυρώθηκε.';

  @override
  String get ocrFailedModel =>
      'Το γλωσσικό μοντέλο λείπει ή είναι κατεστραμμένο. Ξαναεγκατάστησε την εφαρμογή.';

  @override
  String get ocrFailedImage => 'Η εικόνα δεν μπόρεσε να διαβαστεί.';

  @override
  String get ocrFailedTooLarge =>
      'Η εικόνα είναι πολύ μεγάλη για ανάγνωση (πάνω από 400 megapixels).';

  @override
  String get ocrFailedUnsupported =>
      'Η ανάγνωση κειμένου δεν είναι διαθέσιμη εδώ.';

  @override
  String get ocrFailedEngine => 'Η ανάγνωση αυτής της σελίδας απέτυχε.';

  @override
  String get ocrSettingsTitle => 'Γλώσσα ανάγνωσης κειμένου (OCR)';

  @override
  String get ocrSettingsNote =>
      'Επίλεξε το πακέτο που ταιριάζει στα έγγραφά σου. Η εφαρμογή δεν '
      'μαντεύει τη γλώσσα: μια ελληνική σελίδα που διαβάζεται με το λατινικό '
      'πακέτο, ή μια γαλλική με το ελληνικό, βγαίνει λάθος. Όλα διαβάζονται '
      'πάνω στο κινητό, τίποτα δεν στέλνεται κάπου.';

  @override
  String ocrPackName(String packId) => switch (packId) {
    'greek' => 'Ελληνικά + Αγγλικά',
    'latin' => 'Λατινική γραφή',
    _ => packId,
  };

  @override
  String ocrPackDescription(String packId) => switch (packId) {
    'greek' => 'Ελληνικό και αγγλικό κείμενο.',
    'latin' =>
      'Αγγλικά και γλώσσες με λατινικά γράμματα και τόνους: γερμανικά, '
          'γαλλικά, ισπανικά, ιταλικά, πορτογαλικά κ.ά. Δεν διαβάζει ελληνικά.',
    _ => '',
  };

  @override
  String get licensesOpen => 'Άδειες ανοιχτού λογισμικού';
}
