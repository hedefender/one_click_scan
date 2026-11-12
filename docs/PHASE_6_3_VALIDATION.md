# Phase 6.3 (Polish): έλεγχος στο κινητό (όριο σελίδων Multi Page, οδηγός και Βοήθεια, κουμπί λήψης)

Απόφαση και λόγοι: ADR-032 (`docs/DECISIONS.md`). Αρχιτεκτονική: `docs/ARCHITECTURE.md` ενότητα 8k.
Προηγούμενος έλεγχος: `docs/PHASE_6_2_1_VALIDATION.md`.

## 1. Τι άλλαξε για τον χρήστη

- **Όριο σελίδων στο Multi Page.** Έως 25 σελίδες και μέγεθος PDF έως το όριο του παρόχου (Gmail περίπου 18,2 MB, Outlook και Yahoo περίπου 14,6 MB, από την ίδια πηγή που ελέγχει και η αποστολή). Το όριο «XX» υπολογίζεται ξανά μετά από κάθε σελίδα. Πριν την 5η σελίδα φαίνεται «Σελίδες: 3», από την 5η «Σελίδες: 5/18» (νωρίτερα, αν οι σελίδες έχουν ήδη περάσει το 50% του ορίου). Με 2 σελίδες ή λιγότερες να απομένουν βγαίνει μήνυμα «χωράνε ακόμα περίπου N». Στο όριο η λήψη δεν επιτρέπεται, με μήνυμα που προτείνει «Τέλος». Ισχύει σε One Click Multi και σε Multi με προεπισκόπηση. Ο έλεγχος μεγέθους στο τέλος της αποστολής δεν άλλαξε.
- **Wizard:** σε κάθε βήμα επιλογής (φάκελος, email, Gallery) προστέθηκε «Μπορείς να το αλλάξεις αργότερα στις Ρυθμίσεις», και στο email μια γραμμή για το τι είναι πάροχος και παραλήπτης. Μετά την τελευταία ρύθμιση υπάρχει **έκτη σελίδα** με τον οδηγό (δεν ρωτά τίποτα). Οι ρυθμίσεις αποθηκεύονται όπως πριν στο τελευταίο βήμα επιλογής.
- **Βοήθεια** στις Ρυθμίσεις: το ίδιο περιεχόμενο πιο αναλυτικά, σε ενότητες, με την ενότητα «Τι δεν καλύπτει η εφαρμογή» (μόνο εκεί) και το «Δες ξανά τον οδηγό» (χωρίς να ξαναρωτά ρυθμίσεις).
- **Πρώτο άνοιγμα Multi Page:** ένα μικρό παράθυρο με 4 γραμμές, μία φορά.
- **Κουμπί λήψης:** η αναμονή μετρήθηκε. Το μισό ήταν δική μας αναμονή (για τον αναλυτή φωτός) και έφυγε. Για το υπόλοιπο (η κάμερα βγάζει τη φωτογραφία) το κουμπί δείχνει ότι είναι απασχολημένο (θαμπό, με μικρό κύκλο φόρτωσης).
- **Ρυθμός αναλυτή:** μόνο έλεγχος και καταγραφή (ενότητα 3.4). Δεν άλλαξε τίποτα.

## 2. Τι εγκαθιστάς

- **APK:** δεν παραδόθηκε νέο APK. Το χτίζεις με `flutter build apk --release` (ή `--debug`) και το εγκαθιστάς εσύ. Ο `Test_Phone` και το κινητό σου δεν αγγίχτηκαν.
- Κανένα νέο πακέτο, άρα το `THIRD_PARTY_NOTICES.md` δεν αλλάζει.

## 3. Τι ελέγχθηκε στο PC και στον emulator (`Claude_Code_Test`)

| Έλεγχος | Αποτέλεσμα |
|---|---|
| `flutter analyze` (απλό) | Καμία παρατήρηση |
| `flutter test` | 1249 πράσινα (1178 πριν, +71 νέα) |
| `PageBudgetEstimator` (21 τεστ): πριν και μετά τις 5 σελίδες, εμφάνιση στο 50%, όριο 25, περιθώριο, όριο ανά πάροχο, εκτίμηση κάτω από τον αριθμό σελίδων, πολύ μικρές και πολύ μεγάλες σελίδες | Πράσινα |
| Cubit και widget: το μέγεθος των σελίδων από την ουρά, μετρητής «n/XX», μήνυμα «χωράνε ακόμα», αποκλεισμός λήψης (και στα δύο flows), το undo δίνει πίσω τη λήψη, κουμπί «απασχολημένο», πρώτο άνοιγμα Multi (μία φορά, και μετά από επανεκκίνηση) | Πράσινα |
| Wizard (6 βήματα, σημειώσεις «αλλάζει αργότερα», τελική σελίδα με την τελευταία γραμμή, χωρίς «Τι δεν καλύπτει»), Βοήθεια (ενότητες, «Δες ξανά τον οδηγό» χωρίς ερωτήσεις, υπάρχουσα εγκατάσταση), ένα κείμενο για wizard και Βοήθεια | Πράσινα |
| Emulator, όλα τα integration tests | Πράσινα και τα 18 αρχεία: `camera_smoke`, `capture_timing` (νέο), `crop_flow`, `first_run_flow`, `gallery_copy`, `light_camera`, `light_flow`, `mail_flow`, `ocr_engine`, `ocr_flow`, `ocr_release_smoke`, `one_click_flow`, `page_limit_flow` (νέο), `pdf_flow`, `processing_measure`, `scan_flow`, `settings_flow`, `torch_camera`. Το `first_run_flow` και το `settings_flow` ενημερώθηκαν για την έκτη σελίδα του wizard. Το mail και το PDF τρέχουν με τα δικά τους scripts (`run_mail_integration_test.sh`, `run_pdf_integration_test.sh`) |

### 3.1 Τι ήταν γνωστό ανάμεσα στις λήψεις

Το PDF χτίζεται στο τέλος, αλλά η ουρά (`OcrSession`) ετοιμάζει κάθε σελίδα στο παρασκήνιο αμέσως μετά τη λήψη (ορθή εικόνα και crop). **Αυτό το JPEG μπαίνει στο PDF όπως είναι** (χωρίς νέα συμπίεση). Άρα το μέγεθος αυτού του αρχείου είναι το μέγεθος της σελίδας στο PDF και είναι γνωστό πριν το OCR. Σελίδα που δεν έχει ετοιμαστεί ακόμα (γρήγορες λήψεις) μετράει ως ο μέσος όρος των άλλων· πριν από οποιαδήποτε μέτρηση χρησιμοποιείται 1,5 MB. Το μέγεθος της αρχικής φωτογραφίας δεν χρησιμοποιείται.

### 3.2 Ακρίβεια της εκτίμησης (συνθετικές σελίδες, πραγματικός writer PDF)

| Μέτρηση | Αποτέλεσμα |
|---|---|
| Σφάλμα αθροίσματος (μετρημένα μεγέθη + overheads, έναντι πραγματικού PDF), σάρωση 5, 15 και 25 σελίδων | μέσο 1,0%, μέγιστο 1,5% (οι προεπιλογές υπερεκτιμούν λίγο, επίτηδες) |
| Overheads που μετρήθηκαν | περίπου 3,5 KB μία φορά και περίπου 1 KB ανά σελίδα (120 λέξεις). Προεπιλογές 24 KB και 3 KB |
| Σφάλμα προβολής (από τις πρώτες k σελίδες για όλη τη σάρωση) | μέσο 11%, **μέγιστο 47%** όταν οι σελίδες είναι πολύ διαφορετικές (κενή, κείμενο, φωτογραφία στην ίδια σάρωση). **Μεγαλύτερο από το περιθώριο 10%** |
| Προσομοίωση: σάρωση μέχρι το όριο του budget, 2000 σάρωσεις ανά περίπτωση, τρία είδη σάρωσης | με περιθώριο 0,9 **καμία δεν ξεπέρασε το όριο**, χειρότερη 99% του ορίου (μείγμα σελίδων), μέση πλήρωση 88%. Με 0,95: 5,3% των μικτών σάρωσεων ξεπέρασε το όριο |
| Emulator, πραγματική ροή (OCR, crop, PDF) | `integration_test/page_limit_flow_test.dart` (πραγματικό OCR, crop, PDF, φάκελος στον δίσκο, φωτογραφίες κείμενο / υφή / σχεδόν κενή): με πάροχο που παίρνει PDF 3 MB η λήψη μπλοκάρεται στη 5η σελίδα («Σελίδες: 5/5»), το PDF είναι 2489 KB (όριο 3072 KB), εκτίμηση 2514 KB, **σφάλμα 1,0%**. Σάρωση 6 μικτών σελίδων με Gmail: XX=25, εκτίμηση 2602 KB, πραγματικό 2574 KB, **σφάλμα 1,1%** |

**Γιατί το σφάλμα προβολής δεν καθορίζει το αποτέλεσμα:** το όριο υπολογίζεται ξανά μετά από κάθε σελίδα και η στάση αποφασίζεται από το **πραγματικό** άθροισμα μέχρι εκείνη τη στιγμή. **Πρόταση:** κράτα 0,9. Αν στο κινητό δεις σάρωση πάνω από 97% του ορίου, κατέβασέ το σε 0,85 (χειρότερη 94%, μέση πλήρωση 83%). Τα μεγέθη σελίδων της προσομοίωσης είναι υποθέσεις· τα πραγματικά περιμένουν το κινητό.

### 3.3 Το κουμπί λήψης: αιτία και μέτρηση (emulator, 12 γρήγορες λήψεις με τον αναλυτή ενεργό)

| Στάδιο | Πριν | Μετά |
|---|---|---|
| Αναμονή για τον αναλυτή φωτός | **535 ms** μέσος όρος (μέγιστο 807) | **22 ms** (μέγιστο 96) |
| `takePicture` (η κάμερα) | 509 ms | 511 ms |
| Μεταφορά αρχείου στην cache | περίπου 40 ms | περίπου 40 ms |
| **Σύνολο ανενεργού κουμπιού** | **1082 ms** (μέγιστο 1372) | **592 ms** (μέγιστο 822) |

Αιτία: το `_stopAnalysis` περίμενε το τέλος του ύπνου 400 ms του βρόχου του αναλυτή. Τώρα ο βρόχος ξυπνά αμέσως όταν ζητηθεί στάση (το image stream σταματά και πάλι πριν το `takePicture`, με την ίδια σειρά). Δεν υπάρχει backpressure της ουράς OCR (η λήψη δεν περιμένει το OCR στο Multi) ούτε αναμονή αποθήκευσης. Το υπόλοιπο είναι εγγενής καθυστέρηση της κάμερας και δεν κρύβεται: το κουμπί δείχνει «Λήψη...». Οι αριθμοί του κινητού θα είναι άλλοι.

### 3.4 Ρυθμός δειγμάτων του αναλυτή (μόνο εύρημα)

Στον emulator: περίπου 1,27 δείγμα το δευτερόλεπτο (19 δείγματα σε 15 s), ένα δείγμα κάθε 780 με 820 ms. Ο σχεδιασμός έλεγε περίπου 2,5, που ήταν 1 / 400 ms και αφήνει έξω τον ίδιο τον κύκλο (άνοιγμα του image stream, αναμονή για ένα frame, κλείσιμο, μέτρηση), που παίρνει περίπου 380 με 415 ms. Δεν είναι σφάλμα και δεν άλλαξε τίποτα. Αν ο ρυθμός στο κινητό είναι πολύ διαφορετικός είναι για τον έλεγχο στο κινητό.

### 3.5 `flutter analyze` σε καθαρό αντίγραφο

| Έλεγχος | Αποτέλεσμα |
|---|---|
| Πραγματικό `git clone` του HEAD (πριν τις αλλαγές αυτής της φάσης) από το τοπικό path: `tool/fetch_ocr_models.sh`, `flutter pub get`, `flutter analyze` | Καμία παρατήρηση (8,5 s). Ο προσωρινός φάκελος διαγράφηκε |
| Οι αλλαγές της φάσης (δεν είναι committed, άρα όχι πραγματικό clone): αντίγραφο με `git ls-files -co --exclude-standard`, χωρίς `.dart_tool`, ίδια βήματα | Καμία παρατήρηση (12,1 s). Αντίγραφο με `git ls-files -co --exclude-standard` (όχι `git clone`), χωρίς `.dart_tool`. Ο προσωρινός φάκελος διαγράφηκε |

**Δεν ελέγχθηκαν (μόνο κινητό):** τα πραγματικά μεγέθη σελίδων από κάμερα κινητού και άρα το πραγματικό περιθώριο· το πώς φαίνεται και αισθάνεται το κουμπί λήψης· ο ρυθμός του αναλυτή στο κινητό· η ανάγνωση των κειμένων σε μικρή οθόνη.

## 4. Έλεγχος στο κινητό

### 4.1 Όριο σελίδων

| Έλεγχος | Αναμενόμενο | Αποτέλεσμα |
|---|---|---|
| Multi Page, σελίδες 1 έως 4 | Φαίνεται «Σελίδες: n» | |
| 5η σελίδα | Φαίνεται «Σελίδες: 5/XX» | |
| Σελίδες πολύ διαφορετικού μεγέθους (σελίδα με φωτογραφία και σελίδα με λίγο κείμενο) | Το XX αλλάζει (ανεβαίνει ή κατεβαίνει) | |
| Δύο σελίδες πριν το όριο | Μήνυμα «χωράνε ακόμα περίπου N σελίδες» | |
| Στο όριο | Η λήψη δεν επιτρέπεται, μήνυμα που εξηγεί και προτείνει «Τέλος». Το «Τέλος» δουλεύει | |
| «Τέλος» και αποστολή | Το PDF δεν ξεπερνά το όριο του παρόχου, η αποστολή περνά | |
| Το ίδιο σε One Click Multi και σε Multi με προεπισκόπηση | Ίδια συμπεριφορά | |
| Σάρωση 5 σελίδων, με Gmail: εκτίμηση (n/XX και μέγεθος) έναντι πραγματικού μεγέθους PDF | Καταγραφή και σφάλμα % | |
| Σάρωση 15 σελίδων, με Gmail | Ίδιο | |
| Σάρωση 25 σελίδων, με Gmail (ή μέχρι το όριο) | Ίδιο | |
| Σάρωση 5, 15 και 25 σελίδων με πάροχο ορίου 14,6 MB (Outlook ή Yahoo) | Το XX είναι μικρότερο από του Gmail για τις ίδιες σελίδες. Καταγραφή | |
| Αν κάποια σάρωση ξεπέρασε το 97% του ορίου | Πρόταση: περιθώριο 0,85 | |

### 4.2 Wizard

| Έλεγχος | Αναμενόμενο | Αποτέλεσμα |
|---|---|---|
| Βήματα φάκελος, email, Gallery | Κάθε βήμα λέει σύντομα τι σημαίνει η επιλογή και ότι αλλάζει στις Ρυθμίσεις | |
| Βήμα email | Υπάρχει η γραμμή για πάροχο και παραλήπτη | |
| Μετά τη σάρωση τρόπου λειτουργίας (One Click ή προεπισκόπηση) | Εμφανίζεται έκτη σελίδα «Πριν ξεκινήσεις» | |
| Η τελική σελίδα | Έχει: Μία/Πολλές σελίδες και αλλαγή τρόπου, φλας (Κλειστό, Αυτόματο, Φακός και ότι ο Φακός γίνεται Αυτόματο), χαμηλός φωτισμός, συμβουλές λήψης, ακύρωση και απόρριψη, όριο σελίδων και email, ιδιωτικότητα | |
| Τελευταία γραμμή | «Τα παραπάνω τα βρίσκεις πάντα στις Ρυθμίσεις, στη Βοήθεια.» | |
| «Τέλος» στην τελική σελίδα | Πηγαίνει στην αρχική οθόνη | |
| Κλείσιμο της εφαρμογής στην τελική σελίδα | Την επόμενη φορά ανοίγει η αρχική (οι ρυθμίσεις είχαν αποθηκευτεί) | |

### 4.3 Βοήθεια

| Έλεγχος | Αναμενόμενο | Αποτέλεσμα |
|---|---|---|
| Ρυθμίσεις, «Βοήθεια» | Ανοίγει η οθόνη με ενότητες: τρόπος λειτουργίας, φλας και φωτισμός, χαμηλός φωτισμός, συμβουλές, πολλές σελίδες και όριο, email και κωδικός εφαρμογής, ακύρωση και απόρριψη, ιδιωτικότητα, **Τι δεν καλύπτει η εφαρμογή** | |
| «Άνοιγμα ρυθμίσεων email» | Γυρίζει στις Ρυθμίσεις (εκεί είναι ο οδηγός ανά πάροχο) | |
| «Δες ξανά τον οδηγό» | Δείχνει την τελική σελίδα του wizard, **δεν ρωτά ρυθμίσεις**, το «Κλείσιμο» γυρίζει στη Βοήθεια | |
| Υπάρχουσα εγκατάσταση (wizard ήδη τελειωμένο) | Η Βοήθεια υπάρχει, ο wizard δεν ξαναρχίζει | |
| Η τελική σελίδα του wizard | **Δεν** έχει την ενότητα «Τι δεν καλύπτει η εφαρμογή» ούτε την ενότητα email | |

### 4.4 Πρώτο άνοιγμα Multi

| Έλεγχος | Αναμενόμενο | Αποτέλεσμα |
|---|---|---|
| Πρώτη φορά που πατάς «Πολλές σελίδες» (μετά από καθαρή εγκατάσταση ή «Εκκαθάριση δεδομένων») | Μικρό παράθυρο με 4 γραμμές | |
| Ξανά «Μία σελίδα» και «Πολλές σελίδες», και μετά επανεκκίνηση της εφαρμογής | Δεν ξαναβγαίνει | |
| «Μία σελίδα» για πρώτη φορά | Δεν βγαίνει παράθυρο | |

### 4.5 Κουμπί λήψης

| Έλεγχος | Αναμενόμενο | Αποτέλεσμα |
|---|---|---|
| Γρήγορες λήψεις σε Multi: πόσο ώρα μένει ανενεργό (πριν: περίπου 0,5 s) | Σαφώς μικρότερο από πριν (στον emulator: 1,08 s σε 0,59 s). Καταγραφή | |
| Όσο διαρκεί η λήψη | Το κουμπί φαίνεται θαμπό με μικρό κύκλο φόρτωσης, δεν δίνει την αίσθηση ότι κόλλησε | |
| Αναλυτής (ένδειξη «Χαμηλός φωτισμός») μετά τις αλλαγές | Συνεχίζει να δουλεύει και μετά από λήψη | |
| Φακός με γρήγορες λήψεις | Μένει αναμμένος χωρίς τρεμόπαιγμα | |

## 5. Όλα τα νέα κείμενα (EL / EN) για έλεγχο από σένα

Τα κείμενα αυτού του πίνακα βγήκαν αυτόματα από τον κώδικα (`AppStrings`), άρα είναι ακριβώς αυτά που θα δεις στην εφαρμογή. Πες μου ποια θέλεις αλλαγμένα πριν τα δείξουμε σε κανέναν. Σημείωση: η τελευταία γραμμή του οδηγού ήταν «...στο Βοήθεια.» και διορθώθηκε σε «...στη Βοήθεια.» στη Phase 6.4.

### Wizard steps

| Where | Greek | English |
|---|---|---|
| Folder, e-mail, Gallery: added line | Μπορείς να το αλλάξεις αργότερα στις Ρυθμίσεις. | You can change this later in Settings. |
| E-mail step: added note | Πάροχος: το email από το οποίο στέλνεται η σάρωση. Παραλήπτης: η διεύθυνση που τη λαμβάνει, συνήθως το δικό σου email. | Provider: the email account the scan is sent from. Recipient: the address that receives it, usually your own email. |

### Last page of the wizard / guide page

| Where | Greek | English |
|---|---|---|
| Page title | Πριν ξεκινήσεις | Before you start |
| Intro | Τα βασικά, με λίγα λόγια. | The basics, in a few words. |
| Last line | Τα παραπάνω τα βρίσκεις πάντα στις Ρυθμίσεις, στη Βοήθεια. | You can always find the above in Settings, under Help. |
| Close button (guide page from Help) | Κλείσιμο | Close |

### The sections (one source, used by the wizard page and by Help)

| Where | Greek | English |
|---|---|---|
| mode (wizard + Help): title | Τρόπος λειτουργίας | How it works |
| mode (wizard + Help): line 1 | Μία σελίδα: μία λήψη και η σάρωση ολοκληρώνεται. | Single page: one photo and the scan is done. |
| mode (wizard + Help): line 2 | Πολλές σελίδες: τραβάς όσες σελίδες θέλεις και πατάς «Τέλος». | Multiple pages: take as many pages as you need, then tap "Done". |
| mode (wizard + Help): line 3 | Αλλάζεις τρόπο από την κάμερα, πριν τραβήξεις την πρώτη σελίδα. | You change the mode on the camera screen, before the first page. |
| mode (wizard + Help): detail 1 (Help only) | Με το One Click, η σάρωση στέλνεται αμέσως μόλις τελειώσει. Με προεπισκόπηση, βλέπεις πρώτα το PDF και μετά το στέλνεις ή το απορρίπτεις. Το αλλάζεις στις Ρυθμίσεις, στην ενότητα Σάρωση. | With One Click, the scan is sent as soon as it is ready. With preview, you see the PDF first and then send or discard it. You change it in Settings, under Scan. |
| flash (wizard + Help): title | Φλας και φωτισμός | Flash and light |
| flash (wizard + Help): line 1 | Κλειστό: χωρίς φως. | Off: no light. |
| flash (wizard + Help): line 2 | Αυτόματο: το φλας ανάβει στη λήψη, όταν χρειάζεται. | Auto: the flash fires on the shot, when needed. |
| flash (wizard + Help): line 3 | Φακός: το φως μένει αναμμένο όσο είσαι στην κάμερα. | Torch: the light stays on while you are on the camera screen. |
| flash (wizard + Help): line 4 | Ο φακός σβήνει μόνος του μετά από 2 λεπτά χωρίς λήψη. Όταν ξανανοίξεις την εφαρμογή, ο «Φακός» γυρίζει σε «Αυτόματο». | The torch switches itself off after 2 minutes without a shot. When you reopen the app, "Torch" goes back to "Auto". |
| flash (wizard + Help): detail 1 (Help only) | Το κουμπί του φλας φαίνεται μόνο αν το κινητό έχει φλας. | The flash button only shows if the phone has a flash. |
| flash (wizard + Help): detail 2 (Help only) | Όταν βγεις από την κάμερα, ο φακός σβήνει. Αν γυρίσεις στην ίδια σάρωση με επιλογή «Φακός», ανάβει ξανά. | When you leave the camera screen, the torch goes out. If you come back to the same scan with "Torch", it lights again. |
| lowLight (wizard + Help): title | Χαμηλός φωτισμός | Low light |
| lowLight (wizard + Help): line 1 | Η ένδειξη «Χαμηλός φωτισμός» ή το μήνυμα «Σκοτεινή λήψη» σημαίνει ότι η σελίδα είναι σκοτεινή και το κείμενο ίσως δεν διαβαστεί καλά. | The "Low light" mark or the "Dark shot" message means the page is dark and the text may not be read well. |
| lowLight (wizard + Help): line 2 | Πρόσθεσε φως, άναψε τον φακό ή πάτα «Νέα λήψη». | Add light, turn on the torch, or tap "New shot". |
| lowLight (wizard + Help): detail 1 (Help only) | Μετά από μια σκοτεινή λήψη μπορείς να συνεχίσεις ούτως ή άλλως ή να ζητήσεις διόρθωση φωτός. Η διόρθωση είναι απλή και δεν σώζει πολύ σκοτεινές σελίδες· τότε η νέα λήψη είναι η καλύτερη επιλογή. | After a dark shot you can continue anyway or ask for a light correction. The correction is simple and does not rescue very dark pages; then a new shot is the best choice. |
| tips (wizard + Help): title | Συμβουλές για καλή λήψη | Tips for a good shot |
| tips (wizard + Help): line 1 | Καλό φως, ομοιόμορφο πάνω σε όλη τη σελίδα. | Good light, even across the whole page. |
| tips (wizard + Help): line 2 | Απόφυγε τη σκιά του χεριού ή του κινητού πάνω στη σελίδα. | Avoid the shadow of your hand or phone on the page. |
| tips (wizard + Help): line 3 | Σε γυαλιστερό χαρτί απόφυγε την αντανάκλαση: γείρε λίγο τη σελίδα ή άλλαξε γωνία. | On glossy paper avoid reflections: tilt the page a little or change the angle. |
| tips (wizard + Help): line 4 | Βάλε τη σελίδα σε φόντο που ξεχωρίζει από το χαρτί (π.χ. σκούρο τραπέζι για λευκό χαρτί). | Put the page on a background that stands out from the paper (for example a dark table for white paper). |
| tips (wizard + Help): line 5 | Κράτα το κινητό σταθερό. Πάτα πάνω στη σελίδα για εστίαση. | Hold the phone steady. Tap on the page to focus. |
| tips (wizard + Help): detail 1 (Help only) | Η σελίδα να είναι ολόκληρη μέσα στο πλαίσιο και το κινητό παράλληλο με το χαρτί, ώστε το κείμενο να μη φαίνεται λοξό. | Keep the whole page inside the frame and the phone parallel to the paper, so the text does not look slanted. |
| multi (wizard + Help): title | Πολλές σελίδες και όριο | Multiple pages and the limit |
| multi (wizard + Help): line 1 | Τράβα τη μία σελίδα μετά την άλλη. Με το βελάκι αναιρείς την τελευταία. | Take the pages one after the other. The arrow undoes the last one. |
| multi (wizard + Help): line 2 | Πάτα «Τέλος» όταν τελειώσεις, για να αποθηκευτεί και να σταλεί. | Tap "Done" when you finish, to save and send. |
| multi (wizard + Help): line 3 | Όριο: έως 25 σελίδες, και το PDF να χωράει σε ένα email (περίπου 18 MB στο Gmail, περίπου 14 MB σε Outlook και Yahoo). | Limit: up to 25 pages, and the PDF must fit in one email (about 18 MB for Gmail, about 14 MB for Outlook and Yahoo). |
| multi (wizard + Help): line 4 | Από την 5η σελίδα φαίνεται «σελίδα/όριο». Το όριο είναι εκτίμηση και αλλάζει ανάλογα με το μέγεθος των σελίδων. | From the 5th page you see "page/limit". The limit is an estimate and changes with the size of the pages. |
| multi (wizard + Help): detail 1 (Help only) | Όταν φτάσεις το όριο, η λήψη σταματά. Πάτα «Τέλος» και σάρωσε τις υπόλοιπες σελίδες ως νέο έγγραφο. | When you reach the limit, taking photos stops. Tap "Done" and scan the remaining pages as a new document. |
| multi (wizard + Help): detail 2 (Help only) | Πριν την αποστολή το τελικό PDF ελέγχεται ξανά και, αν είναι πολύ μεγάλο, δεν στέλνεται. | Before sending, the final PDF is checked again and, if it is too large, it is not sent. |
| email (Help only): title | Email και κωδικός εφαρμογής | Email and app password |
| email (Help only): line 1 | Η εφαρμογή στέλνει από τον λογαριασμό που διάλεξες, με κωδικό εφαρμογής και όχι με τον κανονικό σου κωδικό. | The app sends from the account you chose, with an app password and not with your normal password. |
| email (Help only): line 2 | Τον κωδικό τον φτιάχνεις στον λογαριασμό σου στον πάροχο. Τα βήματα ανά πάροχο υπάρχουν στις Ρυθμίσεις, στην ενότητα Email. | You make the password in your account at the provider. The steps for each provider are in Settings, under Email. |
| email (Help only): detail 1 (Help only) | Ο κωδικός εφαρμογής είναι ξεχωριστός κωδικός που φτιάχνει ο πάροχος για μία μόνο εφαρμογή. Δεν είναι ο κανονικός κωδικός του λογαριασμού σου, και με ενεργή επαλήθευση σε 2 βήματα ο κανονικός κωδικός δεν γίνεται δεκτός. | An app password is a separate password that the provider makes for one app only. It is not the normal password of your account, and with 2-step verification on, the normal password is not accepted. |
| email (Help only): detail 2 (Help only) | Ο κωδικός φαίνεται μία μόνο φορά: αντίγραψέ τον αμέσως και επικόλλησέ τον χωρίς κενά. Η σελίδα του παρόχου μπορεί να διαφέρει από την περιγραφή. | The password is shown only once: copy it at once and paste it without spaces. The page of the provider may differ from this description. |
| email (Help only): detail 3 (Help only) | Για τον Outlook δεν υπάρχουν βήματα κωδικού εφαρμογής, γιατί προς το παρόν δεν υποστηρίζεται η αποστολή μέσα από την εφαρμογή. Χρειάζεσαι την εφαρμογή Outlook (ή άλλη εφαρμογή email στο κινητό) για να ετοιμαστεί το μήνυμα με το PDF, και το στέλνεις εσύ. Άρα δεν είναι πλήρως «ένα πάτημα» όπως με Gmail και Yahoo. | There are no app password steps for Outlook, because for now sending from inside the app is not supported. You need the Outlook app (or another e-mail app on the phone) to prepare the message with the PDF, and you send it yourself. So it is not fully "one tap" as with Gmail and Yahoo. |
| cancel (wizard + Help): title | Ακύρωση και Απόρριψη | Cancel and Discard |
| cancel (wizard + Help): line 1 | Αν φύγεις από την κάμερα πριν αποθηκευτεί η σάρωση, οι σελίδες που τράβηξες διαγράφονται (η εφαρμογή ρωτά πρώτα). | If you leave the camera before the scan is saved, the pages you took are deleted (the app asks first). |
| cancel (wizard + Help): line 2 | Αν πατήσεις «Ακύρωση» πριν αποθηκευτούν οι φωτογραφίες, δεν μένει τίποτα. Αν ακυρώσεις αφού αποθηκευτούν, μένουν αποθηκευμένες (και το PDF, αν έγινε) και το email δεν στέλνεται. | If you tap "Cancel" before the photos are saved, nothing stays. If you cancel after they are saved, they stay saved (and the PDF, if it was made) and the email is not sent. |
| cancel (wizard + Help): line 3 | Η «Απόρριψη» μιας ολοκληρωμένης σάρωσης σβήνει τις εικόνες, το PDF και το αντίγραφο στη Gallery. Δεν αναιρείται. | "Discard" on a finished scan deletes the images, the PDF and the copy in the Gallery. It cannot be undone. |
| privacy (wizard + Help): title | Ιδιωτικότητα | Privacy |
| privacy (wizard + Help): line 1 | Η ανάγνωση του κειμένου γίνεται στο κινητό σου. Δεν στέλνεται τίποτα πουθενά, εκτός από το email που στέλνεις εσύ. | The text is read on your phone. Nothing is sent anywhere, except the email that you send. |
| privacy (wizard + Help): line 2 | Αν ενεργοποιήσεις την αποθήκευση στη Gallery, η εφαρμογή φωτογραφιών του κινητού (π.χ. Google Photos) μπορεί να συγχρονίσει τα αντίγραφα. Αυτό δεν το ελέγχει η εφαρμογή. | If you enable saving to the Gallery, the photos app of the phone (for example Google Photos) may sync the copies. The app does not control that. |
| notCovered (Help only): title | Τι δεν καλύπτει η εφαρμογή | What the app does not cover |
| notCovered (Help only): line 1 | Η εφαρμογή δεν διορθώνει κακές λήψεις και δεν κάνει προχωρημένη βελτίωση εικόνας. Υπάρχει μόνο μια απλή διόρθωση φωτός, όταν τη ζητήσεις. | The app does not fix bad shots and does not do advanced image improvement. There is only a simple light correction, when you ask for it. |
| notCovered (Help only): line 2 | Η ποιότητα του PDF και του κειμένου εξαρτάται από τη λήψη: φως, σκιά, εστίαση, αντανάκλαση. | The quality of the PDF and of the text depends on the shot: light, shadow, focus, reflection. |
| notCovered (Help only): line 3 | Έλεγξε το PDF και το κείμενο πριν βασιστείς σε αυτά, ιδίως σε ποσά και ημερομηνίες. | Check the PDF and the text before you rely on them, especially amounts and dates. |

### Help screen

| Where | Greek | English |
|---|---|---|
| Settings entry: title | Βοήθεια | Help |
| Settings entry: subtitle | Πώς δουλεύει η σάρωση, συμβουλές λήψης, όρια και ιδιωτικότητα. | How scanning works, tips for good shots, limits and privacy. |
| Help screen title | Βοήθεια | Help |
| Button | Δες ξανά τον οδηγό | See the guide again |
| Button in the e-mail section | Άνοιγμα ρυθμίσεων email | Open email settings |

### First time Multi Page is chosen (pop-up)

| Where | Greek | English |
|---|---|---|
| Title | Πολλές σελίδες | Multiple pages |
| Line 1 (= multi, line 1) | Τράβα τη μία σελίδα μετά την άλλη. Με το βελάκι αναιρείς την τελευταία. | Take the pages one after the other. The arrow undoes the last one. |
| Line 2 (= multi, line 2) | Πάτα «Τέλος» όταν τελειώσεις, για να αποθηκευτεί και να σταλεί. | Tap "Done" when you finish, to save and send. |
| Line 3 (= multi, line 3) | Όριο: έως 25 σελίδες, και το PDF να χωράει σε ένα email (περίπου 18 MB στο Gmail, περίπου 14 MB σε Outlook και Yahoo). | Limit: up to 25 pages, and the PDF must fit in one email (about 18 MB for Gmail, about 14 MB for Outlook and Yahoo). |
| Line 4 (= cancel, line 1) | Αν φύγεις από την κάμερα πριν αποθηκευτεί η σάρωση, οι σελίδες που τράβηξες διαγράφονται (η εφαρμογή ρωτά πρώτα). | If you leave the camera before the scan is saved, the pages you took are deleted (the app asks first). |
| Button | Κατάλαβα | Got it |

### Page limit on the camera screen (Multi Page)

| Where | Greek | English |
|---|---|---|
| Counter before page 5 | Σελίδες: 3 | Pages: 3 |
| Counter from page 5 | Σελίδες: 5/18 | Pages: 5/18 |
| Two pages left | Χωράνε ακόμα περίπου 2 σελίδες στο email (κατά προσέγγιση). | About 2 more pages will fit in the email (approximate). |
| One page left | Χωράει ακόμα περίπου 1 σελίδα στο email (κατά προσέγγιση). | About 1 more page will fit in the email (approximate). |
| Limit reached | Το PDF θα ξεπερνούσε το όριο μεγέθους του email. Πάτα «Τέλος» για να σταλεί και σάρωσε τις υπόλοιπες σελίδες ως νέο έγγραφο. | The PDF would go over the email size limit. Tap "Done" to send it, then scan the remaining pages as a new document. |

### Capture button

| Where | Greek | English |
|---|---|---|
| Accessibility label while a shot is taken | Λήψη... | Taking photo... |
| Accessibility label otherwise (unchanged) | Λήψη | Take photo |

> Note (6.4.1): the flash/torch naming (Off / Auto / Torch), the Outlook, privacy, low-light and cancel texts above were reworded in Phase 6.4.1 (the low-light line was put back in Phase 6.5: the "Dark shot" message does exist). The current wording is in `app_strings_el.dart` and `app_strings_en.dart`; this table shows what 6.3 checked.
