import '../../domain/entities/mail_provider_id.dart';
import '../../domain/mail/mail_outcome.dart';
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

  @override
  String get pdfTitle => 'PDF';

  @override
  String pdfReading(int page, int total) => total <= 1
      ? 'Ανάγνωση του κειμένου…'
      : 'Ανάγνωση σελίδας $page από $total…';

  @override
  String get pdfCreating => 'Δημιουργία του PDF…';

  @override
  String pdfSaved(String fileName) => 'Το PDF αποθηκεύτηκε: $fileName';

  @override
  String pdfDetails(int pages, String size) =>
      pages == 1 ? '1 σελίδα, $size' : '$pages σελίδες, $size';

  @override
  String pdfPagesWithoutText(int count) => count == 1
      ? 'Μία σελίδα δεν έχει κείμενο για αναζήτηση. Η εικόνα της υπάρχει στο PDF.'
      : '$count σελίδες δεν έχουν κείμενο για αναζήτηση. Οι εικόνες τους '
            'υπάρχουν στο PDF.';

  @override
  String get pdfTextNote =>
      'Το κείμενο πίσω από τις εικόνες διαβάζεται αυτόματα και μπορεί να έχει '
      'λάθη. Έλεγχε πάντα το ίδιο το έγγραφο.';

  @override
  String get pdfOpen => 'Άνοιγμα PDF';

  @override
  String get pdfSkipText => 'Δημιουργία του PDF χωρίς αναμονή για το κείμενο';

  @override
  String get pdfRetry => 'Δοκίμασε ξανά';

  @override
  String get pdfWait => 'Περίμενε να ετοιμαστεί το PDF.';

  @override
  String get pdfOpenNoViewer =>
      'Καμία εφαρμογή σε αυτό το κινητό δεν ανοίγει αρχεία PDF.';

  @override
  String get pdfOpenFailed => 'Το PDF δεν μπόρεσε να ανοίξει.';

  @override
  String get pdfFailedImage =>
      'Το PDF δεν δημιουργήθηκε: μια φωτογραφία δεν διαβάζεται ή είναι πολύ '
      'μεγάλη. Οι φωτογραφίες σου αποθηκεύτηκαν.';

  @override
  String get pdfFailedUnsupported =>
      'Η δημιουργία PDF δεν είναι διαθέσιμη σε αυτή τη συσκευή. Οι '
      'φωτογραφίες σου αποθηκεύτηκαν.';

  @override
  String get pdfFailedBuild =>
      'Το PDF δεν δημιουργήθηκε. Οι φωτογραφίες σου αποθηκεύτηκαν.';

  @override
  String get pdfFailedNoAccess =>
      'Το PDF δεν αποθηκεύτηκε: η εφαρμογή δεν έχει πια πρόσβαση στον φάκελό '
      'σου. Οι φωτογραφίες σου αποθηκεύτηκαν. Διάλεξε ξανά τον φάκελο στις '
      'Ρυθμίσεις.';

  @override
  String get pdfFailedWrite =>
      'Το PDF δεν γράφτηκε στον φάκελό σου (είναι γεμάτος ο χώρος;). Οι '
      'φωτογραφίες σου αποθηκεύτηκαν.';

  @override
  String get mailPasswordLabel => 'Κωδικός εφαρμογής';

  @override
  String get mailPasswordShow => 'Εμφάνιση του κωδικού';

  @override
  String get mailPasswordHide => 'Απόκρυψη του κωδικού';

  @override
  String get mailPasswordStored =>
      'Ένας κωδικός είναι αποθηκευμένος σε αυτό το κινητό.';

  @override
  String get mailPasswordNone => 'Δεν υπάρχει αποθηκευμένος κωδικός.';

  @override
  String get mailPasswordPrivacy =>
      'Ο κωδικός αποθηκεύεται κρυπτογραφημένος στο κινητό (Android Keystore). '
      'Δεν μπαίνει στα αντίγραφα ασφαλείας και δεν γράφεται πουθενά αλλού.';

  @override
  String get mailPasswordDelete => 'Διαγραφή αποθηκευμένου κωδικού';

  @override
  String get mailPasswordDeleted => 'Ο κωδικός διαγράφηκε.';

  @override
  String get mailPasswordDeleteFailed => 'Ο κωδικός δεν μπόρεσε να διαγραφεί.';

  @override
  String get mailTest => 'Δοκιμή σύνδεσης';

  @override
  String get mailTestRunning => 'Δοκιμή σύνδεσης…';

  @override
  String get mailTestOk =>
      'Ο διακομιστής δέχτηκε τον λογαριασμό. Δεν στάλθηκε κανένα μήνυμα.';

  @override
  String get mailTestNeedsPassword =>
      'Γράψε πρώτα τον κωδικό εφαρμογής (ή αποθήκευσέ τον).';

  @override
  String get mailModeTitle => 'Τρόπος αποστολής';

  @override
  String get mailModeSend => 'Αποστολή από την εφαρμογή';

  @override
  String get mailModeShare => 'Άνοιγμα στην εφαρμογή email';

  @override
  String get mailModeShareNote =>
      'Με το «Άνοιγμα στην εφαρμογή email» ανοίγει η εφαρμογή email σου με '
      'έτοιμο παραλήπτη, θέμα και PDF, και πατάς εσύ αποστολή εκεί. Δεν '
      'χρειάζεται κωδικός εφαρμογής. Θα χρησιμοποιηθεί ο λογαριασμός που έχει '
      'ήδη επιλεγμένο η εφαρμογή email.';

  @override
  String get mailHelpTitle => 'Πώς φτιάχνεται ο κωδικός εφαρμογής';

  @override
  List<String> mailHelpSteps(MailProviderId provider) => switch (provider) {
    MailProviderId.gmail => const [
      'Βεβαιώσου ότι ο λογαριασμός Google έχει ενεργή επαλήθευση σε 2 βήματα.',
      'Πάτησε «Άνοιγμα σελίδας του παρόχου». Θα ανοίξει στον browser και '
          'μπορεί να ζητήσει να συνδεθείς.',
      'Ακολούθησε τη σελίδα για να φτιάξεις έναν κωδικό εφαρμογής (αν ζητηθεί '
          'όνομα, γράψε π.χ. One Click Scan).',
      'Αντίγραψε τον κωδικό και επικόλλησέ τον πιο πάνω, χωρίς κενά.',
    ],
    MailProviderId.outlook => const [],
    MailProviderId.yahoo => const [
      'Πάτησε «Άνοιγμα σελίδας του παρόχου». Θα ανοίξει στον browser η '
          'ασφάλεια λογαριασμού του Yahoo (Account Security).',
      'Στην ενότητα «External connections» πάτησε «Create app password».',
      'Γράψε ένα όνομα (π.χ. One Click Scan) και πάτησε «Generate password».',
      'Αντίγραψε τον κωδικό και επικόλλησέ τον πιο πάνω, χωρίς κενά.',
    ],
  };

  @override
  String? mailHelpNote(MailProviderId provider) => switch (provider) {
    MailProviderId.gmail =>
      'Χρειάζεται ενεργή επαλήθευση σε 2 βήματα. Η επιλογή δεν υπάρχει σε '
          'λογαριασμούς με κλειδιά ασφαλείας μόνο, σε λογαριασμούς εργασίας ή '
          'σχολείου (ο διαχειριστής μπορεί να την απαγορεύει) και με '
          'Advanced Protection. Τότε χρησιμοποίησε την εφεδρική αποστολή.',
    MailProviderId.outlook => null,
    MailProviderId.yahoo =>
      'Για τη δημιουργία, το Yahoo ζητά browser στον οποίο έχεις συνδεθεί '
          'εδώ και μέρες, όχι ανώνυμη περιήγηση. $mailYahooSizeNote',
  };

  @override
  String get mailOutlookWarning =>
      'Ο Outlook δεν δέχεται ακόμα αποστολή από την εφαρμογή με κωδικό '
      'εφαρμογής. Θα υποστηριχθεί μετά την υλοποίηση OAuth. Προς το παρόν '
      'χρησιμοποίησε την εφεδρική αποστολή (άνοιγμα στην εφαρμογή email).';

  @override
  String get mailYahooSizeNote =>
      'Το Yahoo δεν δηλώνει επίσημα όριο μεγέθους. Η εφαρμογή θεωρεί ότι το '
      'μήνυμα χωράει έως 20 MB.';

  @override
  String get mailGuideWhat =>
      'Ο κωδικός εφαρμογής είναι ξεχωριστός κωδικός που φτιάχνει ο πάροχος για '
      'μία μόνο εφαρμογή. Δεν είναι ο κανονικός κωδικός του λογαριασμού σου, '
      'και με ενεργή επαλήθευση σε 2 βήματα ο κανονικός κωδικός δεν γίνεται '
      'δεκτός.';

  @override
  String get mailGuideReminder =>
      'Ο κωδικός φαίνεται μία μόνο φορά: αντίγραψέ τον αμέσως και επικόλλησέ '
      'τον χωρίς κενά. Η σελίδα του παρόχου μπορεί να διαφέρει από την '
      'περιγραφή.';

  @override
  String get mailGuideOpenPage => 'Άνοιγμα σελίδας του παρόχου';

  @override
  String get mailGuideOpenFailed =>
      'Δεν άνοιξε browser. Άνοιξε χειροκίνητα τη σελίδα ασφάλειας του '
      'λογαριασμού σου.';

  @override
  String get mailGuideOpenSettings => 'Οδηγός κωδικού εφαρμογής';

  @override
  String get mailGuideOutlook =>
      'Για τον Outlook δεν υπάρχουν βήματα κωδικού εφαρμογής: δεν υποστηρίζεται '
      'για αποστολή. Θα υποστηριχθεί μετά την υλοποίηση OAuth. Προς το παρόν '
      'χρησιμοποίησε την εφεδρική αποστολή.';

  @override
  String get mailFallbackButton => 'Χρήση εφεδρικής αποστολής';

  @override
  String get mailFallbackReasonAuth =>
      'Ο πάροχος δεν δέχτηκε κωδικό εφαρμογής για αυτόν τον λογαριασμό. Η '
      'εφεδρική αποστολή ανοίγει την εφαρμογή email σου με έτοιμο το μήνυμα.';

  @override
  String get mailFallbackReasonOutlook =>
      'Ο Outlook δεν υποστηρίζει ακόμα αποστολή με κωδικό εφαρμογής. Η '
      'εφεδρική αποστολή ανοίγει την εφαρμογή email σου με έτοιμο το μήνυμα.';

  @override
  String mailDiagnostic(MailStage stage, int? code) {
    final name = switch (stage) {
      MailStage.connection => 'σύνδεση',
      MailStage.tls => 'TLS',
      MailStage.authentication => 'ταυτοποίηση',
      MailStage.sending => 'αποστολή',
    };
    return code == null ? 'Στάδιο: $name' : 'Στάδιο: $name, κωδικός $code';
  }

  @override
  String get mailSendTitle => 'Email';

  @override
  String mailSendTo(String destination) =>
      'Το PDF θα σταλεί στη διεύθυνση $destination.';

  @override
  String get mailSendButton => 'Αποστολή';

  @override
  String get mailShareButton => 'Άνοιγμα στην εφαρμογή email';

  @override
  String get mailShareNote =>
      'Θα ανοίξει η εφαρμογή email σου με έτοιμο το μήνυμα και το PDF. Θα '
      'χρησιμοποιηθεί ο λογαριασμός που έχει ήδη επιλεγμένο η εφαρμογή email. '
      'Το μήνυμα φεύγει όταν πατήσεις αποστολή εκεί.';

  @override
  String get mailSending => 'Αποστολή σε εξέλιξη…';

  @override
  String get mailCancel => 'Ακύρωση αποστολής';

  @override
  String get mailSent => 'Το μήνυμα στάλθηκε από τον διακομιστή email.';

  @override
  String get mailRetry => 'Δοκίμασε ξανά';

  @override
  String get mailOpenApp => 'Άνοιγμα στην εφαρμογή email';

  @override
  String get mailOpenSettings => 'Άνοιγμα ρυθμίσεων';

  @override
  String get mailNotConfiguredAccount =>
      'Δεν έχει οριστεί λογαριασμός email για αποστολή. Όρισέ τον στις '
      'Ρυθμίσεις.';

  @override
  String get mailNotConfiguredPassword =>
      'Δεν υπάρχει αποθηκευμένος κωδικός εφαρμογής για αυτόν τον λογαριασμό. '
      'Γράψε τον στις Ρυθμίσεις.';

  @override
  String get mailFailedAuth =>
      'Ο διακομιστής δεν δέχτηκε τον λογαριασμό ή τον κωδικό. Με ενεργό MFA '
      '(επαλήθευση σε 2 βήματα) χρειάζεται κωδικός εφαρμογής που φτιάχνεται '
      'στον πάροχο, όχι ο κανονικός κωδικός του λογαριασμού. Σε ορισμένους '
      'λογαριασμούς (π.χ. εταιρικούς ή σχολικούς) ο διαχειριστής δεν '
      'επιτρέπει κωδικούς εφαρμογής.';

  @override
  String get mailFailedNetwork =>
      'Δεν έγινε σύνδεση με τον διακομιστή email. Έλεγξε το internet και '
      'δοκίμασε ξανά.';

  @override
  String get mailFailedTooLarge =>
      'Το PDF είναι πολύ μεγάλο για να σταλεί με email από αυτόν τον πάροχο. '
      'Άνοιξέ το στην εφαρμογή email ή μοιράσου το αλλιώς.';

  @override
  String mailFailedRejected(int code) => code == 0
      ? 'Ο διακομιστής email απέρριψε το μήνυμα.'
      : 'Ο διακομιστής email απέρριψε το μήνυμα (κωδικός $code).';

  @override
  String get mailFailedUnknown =>
      'Το μήνυμα δεν στάλθηκε λόγω απρόσμενου σφάλματος.';

  @override
  String get mailDraftOpened =>
      'Η εφαρμογή email άνοιξε με τον λογαριασμό που έχει ήδη επιλεγμένο. '
      'Πάτησε αποστολή εκεί για να φύγει το μήνυμα.';

  @override
  String get mailDraftOpenedGeneric =>
      'Δεν βρέθηκε εφαρμογή email, οπότε άνοιξε το γενικό μενού κοινοποίησης. '
      'Διάλεξε εφαρμογή για να στείλεις το PDF.';

  @override
  String get mailDraftNoApp =>
      'Δεν βρέθηκε εφαρμογή email που να δέχεται συνημμένο αρχείο.';

  @override
  String get mailDraftFailed =>
      'Το PDF δεν μπόρεσε να δοθεί στην εφαρμογή email.';

  @override
  String get flowTitle => 'Πώς θέλεις να δουλεύει η σάρωση;';

  @override
  String get flowBody =>
      'Με το One Click, η σάρωση επεξεργάζεται και στέλνεται αμέσως μόλις τραβηχτεί. Δεν υπάρχει προεπισκόπηση. Με προεπισκόπηση, βλέπεις πρώτα τις σελίδες και μετά στέλνεις ή απορρίπτεις τη σάρωση. Μπορείς να το αλλάξεις αργότερα στις Ρυθμίσεις.';

  @override
  String get flowOneClick => 'One Click (χωρίς προεπισκόπηση)';

  @override
  String get flowOneClickNote => 'Στέλνεται αμέσως, χωρίς επιβεβαίωση.';

  @override
  String get flowPreview => 'Με προεπισκόπηση';

  @override
  String get flowPreviewNote =>
      'Βλέπεις πρώτα τις σελίδες, μετά στέλνεις ή απορρίπτεις.';

  @override
  String get flowRequired => 'Διάλεξε μία επιλογή για να συνεχίσεις.';

  @override
  String get settingsFlowTitle => 'Σάρωση';

  @override
  String get settingsOneClickToggle =>
      'Λειτουργία One Click (χωρίς προεπισκόπηση)';

  @override
  String get settingsFlowNote =>
      'Όταν είναι ενεργό, η σάρωση επεξεργάζεται και στέλνεται αμέσως μόλις τραβηχτεί, χωρίς προεπισκόπηση. Όταν είναι ανενεργό, βλέπεις πρώτα τις σελίδες και μετά στέλνεις ή απορρίπτεις τη σάρωση.';

  @override
  String get flowCancel => 'Ακύρωση';

  @override
  String get flowSharing => 'Άνοιγμα της εφαρμογής email…';

  @override
  String get flowCancelledReading =>
      'Ακυρώθηκε. Οι εικόνες είναι αποθηκευμένες στον φάκελό σου. Δεν δημιουργήθηκε PDF.';

  @override
  String get flowCancelledSending =>
      'Ακυρώθηκε. Η σάρωση και το PDF είναι αποθηκευμένα. Δεν στάλθηκε τίποτα.';

  @override
  String get flowNotSent => 'Δεν στάλθηκε';

  @override
  String get flowNotSentNote =>
      'Η σάρωση και το PDF είναι αποθηκευμένα. Μπορείς να δοκιμάσεις ξανά.';

  @override
  String get previewTitle => 'Έλεγχος της σάρωσης';

  @override
  String get previewHint =>
      'Δες τις σελίδες και μετά στείλε ή απόρριψε τη σάρωση.';

  @override
  String get previewDiscard => 'Απόρριψη';

  @override
  String get discardConfirmTitle => 'Να διαγραφεί η σάρωση;';

  @override
  String get discardConfirmBody =>
      'Θα διαγραφούν οι εικόνες, το PDF και το αντίγραφο στη Gallery ολόκληρης της σάρωσης. Η διαγραφή δεν αναιρείται.';

  @override
  String get discardConfirmYes => 'Διαγραφή';

  @override
  String get discardConfirmNo => 'Κράτησέ τη';

  @override
  String get discardRunning => 'Διαγραφή…';

  @override
  String get discardDone => 'Η σάρωση διαγράφηκε.';

  @override
  String discardPartial(int pictures, bool pdf, int gallery) {
    final left = <String>[
      if (pictures > 0) pictures == 1 ? '1 εικόνα' : '$pictures εικόνες',
      if (pdf) 'το PDF',
      if (gallery > 0)
        gallery == 1
            ? '1 αντίγραφο στη Gallery'
            : '$gallery αντίγραφα στη Gallery',
    ];
    return 'Δεν διαγράφηκαν όλα. Έμειναν: ${left.join(', ')}.';
  }
}
