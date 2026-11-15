# Phase 6.6 (Δίχτυ ασφαλείας και καθαρισμός μετά το Audit A1): έλεγχος

Αναφορά: `docs/AUDIT_A1.md`. **Καμία αλλαγή συμπεριφοράς της εφαρμογής.** Δεν υπάρχει τίποτα για έλεγχο στο κινητό.

## 1. Τι έγινε

| Εύρημα | Τι έγινε | Αρχεία |
|---|---|---|
| A1-001 | Η ομάδα «the whole screen flow» του `mail_flow_test` ορίζει ψηλή εικονική οθόνη 800x2400 όπως τα άλλα flow τεστ, και υπάρχει `pump` ανάμεσα στο `ensureVisible` και το `tap` (3 σημεία). Αιτία: σφάλμα του τεστ, όχι του κουμπιού | `integration_test/mail_flow_test.dart` |
| A1-002 (μόνο το τεστ) | Η σταθερή αναμονή 3 s έγινε αναμονή με όριο 3 λεπτών ώσπου **κάθε** σελίδα να έχει γνωστό μέγεθος (`ScanState.pageBytes`, υπήρχε ήδη). Ο εκτιμητής δεν αλλάχτηκε | `integration_test/page_limit_flow_test.dart` |
| A1-007 | Νέο `tool/run_all_integration.sh`: όλα τα αρχεία του `integration_test/` και το release smoke (R8), σωστός runner ανά αρχείο, uninstall πριν από κάθε αρχείο, επανεκκίνηση του `Claude_Code_Test` κάθε 2 αρχεία (και μία επανάληψη αν βγει `INSUFFICIENT_STORAGE`), συνέχεια μετά από αποτυχία, σύνοψη και exit code ≠ 0. Μπορεί να τρέξει και μερικά αρχεία. Κανόνας στο `CLAUDE.md` | `tool/run_all_integration.sh`, `CLAUDE.md`, `docs/ARCHITECTURE.md` (ενότητα 9), `README.md` |
| A1-012 | Διαγράφηκε το `android_overlay/`. Διορθώθηκαν τα 4 σχόλια στο `lib/services/`, δύο σημεία της `ARCHITECTURE.md`. Το τεστ που συνέκρινε το αντίγραφο ελέγχει πια ότι ο φάκελος δεν υπάρχει | `lib/services/{image,pdf,scan_files,storage_folder}/…`, `test/android/mail_android_config_test.dart`, `docs/ARCHITECTURE.md` |
| A1-016 | Το interface `AppLogger` μπήκε στο `lib/core/logging/app_logger_interface.dart` χωρίς import του Flutter. Το `app_logger.dart` το κάνει `export` και κρατά το `DebugAppLogger`, άρα τα υπόλοιπα 35 imports δεν άλλαξαν. Τα 5 use cases εισάγουν το νέο αρχείο. Νέος φρουρός `test/domain/domain_purity_test.dart`: κανένα αρχείο του `lib/domain/` δεν εισάγει Flutter, ούτε μέσω των αρχείων του `core/` και `shared/` που εισάγει | `lib/core/logging/*`, 5 use cases, `test/domain/domain_purity_test.dart` |
| A1-018 | Προστέθηκε `*.stackdump` στο `.gitignore`. **Το `git rm --cached bash.exe.stackdump` το κάνεις εσύ** | `.gitignore` |
| Έγγραφα | Καταστάσεις και αποφάσεις στο `AUDIT_A1.md`· 6.6 έως 6.9, πιλοτικό, μετρήσεις, κατάστημα, εξαρτήσεις στο `ROADMAP.md`· πίνακας φάσεων στο `README.md`· `docs/README.md` | `docs/AUDIT_A1.md`, `docs/ROADMAP.md`, `README.md`, `docs/README.md` |
| Έξτρα (τετριμμένο τεστ) | Το `light_camera_test` απέτυχε μία φορά στο πλήρες run: στο τέλος το `camera.close()` διέγραφε τον controller ενώ το `CameraPreview` ήταν ακόμη στο δέντρο. Προστέθηκε `pumpWidget(SizedBox.shrink())` πριν το `close()` | `integration_test/light_camera_test.dart` |

Αρχεία παραγωγής που άλλαξαν: μόνο τα 4 σχόλια (A1-012) και τα αρχεία του logger (A1-016). Καμία άλλη αλλαγή στο `lib/`.

## 2. Αποτελέσματα

| Έλεγχος | Αποτέλεσμα |
|---|---|
| `flutter analyze`, `dart format` | Καμία παρατήρηση |
| `flutter test` | **1345 πράσινα** (1343 πριν, +2 του φρουρού του domain· το τεστ του overlay αντικαταστάθηκε 1 προς 1) |
| Ο φρουρός αποτυγχάνει όταν παραβιάζεται | Ναι: επαναφέροντας προσωρινά ένα use case στο `app_logger.dart` το δεύτερο τεστ έγινε κόκκινο· αναιρέθηκε |
| `mail_flow_test` | **24 από 24** (πριν 22 από 24) |
| `page_limit_flow_test` 5 στη σειρά (uninstall ανάμεσα, επανεκκίνηση emulator πριν την 3η) | **5 από 5**: 94, 97, 118, 95, 101 s. Κάθε φορά: στο όριο 5 σελίδες, εκτίμηση 2514 KB, πραγματικό PDF 2489 KB, σφάλμα 1,0%· 6 μικτές σελίδες εκτίμηση 2602 KB, πραγματικό 2574 KB, σφάλμα 1,1% |
| Debug build μετά τη διαγραφή του `android_overlay/` και integration τεστ | Χτίζει και τρέχει (όλα τα παρακάτω χτίζονται από το `android/`) |

### Πλήρες `tool/run_all_integration.sh` (run `20261115_142730`, 2929 s, περίπου 49 λεπτά)

| Αρχείο | Αποτέλεσμα | s |
|---|---|---|
| about_native_test | OK | 55 |
| camera_smoke_test | OK | 79 |
| capture_timing_test | OK | 96 |
| crop_flow_test | OK | 259 |
| first_run_flow_test | OK | 86 |
| gallery_copy_test | OK | 56 |
| light_camera_test | **FAILED** (βλ. παρακάτω) | 110 |
| light_flow_test | OK | 103 |
| mail_flow_test | OK | 125 |
| ocr_engine_test | OK | 103 |
| ocr_flow_test | OK | 84 |
| ocr_release_smoke_test | OK | 66 |
| one_click_flow_test | OK | 178 |
| page_limit_flow_test | OK | 97 |
| pdf_flow_test | OK | 200 |
| processing_measure_test | OK | 123 |
| scan_flow_test | OK | 78 |
| screenshots_test | OK | 263 |
| settings_flow_test | OK | 84 |
| torch_camera_test | OK | 71 |
| release smoke (R8, `run_ocr_release_smoke.sh`) | OK | 142 |

20 πράσινα, 1 κόκκινο. **Το `light_camera_test`:** όλες οι μετρήσεις του πέρασαν (αναλυτής σε λειτουργία 1,41 δείγμα/s, λήψη κατά την ανάλυση, εστίαση)· το σφάλμα ήταν στο τέλος, `CameraException(Disposed CameraController, buildPreview() was called on a disposed…)`. Αιτία: **τεστ** (race στο κλείσιμο, βλ. πίνακα 1). Μόνο του πέρασε χωρίς αλλαγή (105 s), και με τη διόρθωση πέρασε μαζί με το `torch_camera_test` (99 και 73 s). Το πλήρες run **δεν** επαναλήφθηκε ολόκληρο μετά τη διόρθωση.

Επιβεβαιώθηκε και ο μηχανισμός του script: επανεκκινήσεις του emulator κάθε 2 αρχεία, κανένα `INSUFFICIENT_STORAGE`, συνέχεια μετά την αποτυχία, σύνοψη και exit code 1.

## 3. Τι δεν ελέγχθηκε

- Τίποτα στο κινητό (δεν χρειάζεται αυτή η φάση).
- Το `run_all_integration.sh` δεν δοκιμάστηκε σε `INSUFFICIENT_STORAGE` (δεν εμφανίστηκε) ούτε σε πλήρες δεύτερο run.
- Τα αρχεία που γράφει το `pdf_flow_test`/`crop_flow_test` (PDF στο `build/integration_logs/<time>/pdf_*`) και τα screenshots δεν ελέγχθηκαν οπτικά (το αποτέλεσμα του τεστ είναι πράσινο).
