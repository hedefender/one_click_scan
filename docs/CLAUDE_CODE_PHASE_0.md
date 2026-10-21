# Οδηγίες προς Claude Code: Phase 0

Διάβασε πρώτα το `CLAUDE.md`, το `docs/ARCHITECTURE.md` και το `docs/PHASE_0_PLAN.md`.
Δεν κάνεις commit ή push. Δεν αγγίζεις τον emulator του χρήστη.

## Κατάσταση

Το repo περιέχει seed κώδικα (`lib/`, `test/`, `integration_test/`, `docs/`,
`pubspec.yaml`, `analysis_options.yaml`, `android_overlay/`) που **δεν έχει μεταγλωττιστεί ποτέ**.
Η δουλειά σου είναι να τον κάνεις να χτίζει, να περνά τα tests και να τρέχει, χωρίς να αλλάξεις την
αρχιτεκτονική. Περιβάλλον χρήστη: Flutter 3.47.7 stable, Dart 3.13.5.

## Βήματα

1. **Έλεγχος εργαλείων.** `flutter --version`, `flutter doctor`. Αν λείπει Android SDK ή emulator, σταμάτα και πες μου τι λείπει.

2. **Δημιουργία πλατφόρμας.** Το seed έχει ήδη `pubspec.yaml`. Μετακίνησέ το προσωρινά έξω από τον φάκελο, τρέξε:
   `flutter create --org com.example --project-name one_click_scan --platforms android .`
   και μετά επανάφερε το δικό μας `pubspec.yaml` και το `analysis_options.yaml` (αντικατάσταση των παραγόμενων).
   Σβήσε το παραγόμενο `test/widget_test.dart` και βεβαιώσου ότι το `lib/main.dart` είναι το δικό μας (όχι το demo counter).

3. **Android overlay.**
   - Αντίγραψε `android_overlay/app/src/main/kotlin/com/example/one_click_scan/MainActivity.kt` πάνω από το παραγόμενο `android/app/src/main/kotlin/com/example/one_click_scan/MainActivity.kt` (αν το package ή το path διαφέρει, προσάρμοσε το `package` και το path και ενημέρωσέ με).
   - Όρισε `minSdk = 24` στο `android/app/build.gradle(.kts)`.
   - Όρισε το label της εφαρμογής σε `One Click Scan` στο `AndroidManifest.xml`.
   - Μην προσθέσεις permissions (το SAF δεν θέλει).

4. **Εξαρτήσεις.** `flutter pub get`, μετά `dart pub upgrade --tighten` ώστε τα `any` να γίνουν `^` constraints. Ανέφερε τις τελικές εκδόσεις.

5. **Μεταγλώττιση.** `dart format .`, `flutter analyze`. Διόρθωσε κάθε error και warning. Αν κάτι απαιτεί αλλαγή του API ενός package (νεότερη έκδοση), προσάρμοσε τον κώδικα με τον ελάχιστο δυνατό τρόπο.

6. **Unit και widget tests.** `flutter test`. Όλα πρέπει να περνούν. Αν ένα test αποτυγχάνει, κρίνε αν φταίει ο κώδικας ή το test και ανέφερε ποιο από τα δύο διόρθωσες και γιατί. Μην αδυνατίζεις ή σβήνεις test για να περάσει.

7. **Integration test** (μόνο στον δικό σου emulator):
   `flutter test integration_test/first_run_flow_test.dart -d <το-δικό-σου-device-id>`
   Αν δεν υπάρχει δικός σου emulator, δημιούργησε έναν (π.χ. AVD `claude_code_emulator`, x86_64) και πες μου το όνομα.

8. **Debug APK.** `flutter build apk --debug`. Ανέφερε το path του APK.

9. **Έλεγχος ιδιωτικότητας.** Βεβαιώσου ότι δεν υπάρχουν προσωπικά δεδομένα ή πραγματικά emails/paths στο repo (μόνο `@example.com` και συνθετικά δεδομένα).

## Τι θέλω ως αναφορά στο τέλος (στα ελληνικά, σύντομα)

- Εκδόσεις Flutter/Dart και τελικές εκδόσεις των packages.
- **Πλήρης λίστα αλλαγών που έκανες στο seed** (αρχείο + τι + γιατί). Αν δεν άλλαξες τίποτα, γράψε το.
- Αποτελέσματα: `flutter analyze`, `flutter test` (πλήθος), integration test.
- Path του debug APK.
- Ό,τι δεν μπόρεσες να ελέγξεις (π.χ. πραγματικό SAF picker: ελέγχεται χειροκίνητα από εμένα, βλ. `docs/PHASE_0_VALIDATION.md`).
- Ανοιχτά ερωτήματα, αν υπάρχουν.

Μετά σταματάς. Δεν προχωράς σε Phase 1.
