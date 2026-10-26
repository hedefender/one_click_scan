# Decisions

## ADR-001 Privacy first, fully local
No developer cloud, mandatory app account, subscription or bank API. Internet
is allowed only for services, optionally, and without sending personal data.
E-mail delivery is started by the user and goes from the user's own account to
the user's chosen recipient; the app itself runs no backend.

## ADR-002 Business logic in Rust (Budget)
Parsing, rule engine and statistics live in Rust in the Budget app. For Scan:
not in Phase 0; candidate in the image processing phase (see ARCHITECTURE §10).

## ADR-003 Independent apps
Scan does not depend on Budget and Budget does not depend on Scan. Only the JSON
contract links them. Scan works standalone (plain documents, mail delivery).

## ADR-004 State management, DI, routing
flutter_bloc (Cubit), get_it (manual registration, new container per build),
go_router. Chosen for testability. Not required to match Budget.

## ADR-005 User-chosen storage folder
The user picks a visible folder at first launch (Android SAF tree URI with
persisted permission). Inside it (`./` below) Scan writes two sub-folders, so
the user can share files to other apps or to their own cloud storage:

- `./pictures/` holds the original JPEGs. They are always saved, so they can be
  shared with tools that do not accept PDF.
- `./pdf/` holds the PDFs.

Naming: both outputs of a scan share one stem, the device time as
`YYYY-MM-DD_HH-MM-SS` (the e-mail subject is `One Click Scan - <stem>`, ADR-020). PDF:
`pdf/<stem>.pdf`. Images: `pictures/<stem>_<n>.jpg`, `n` starting at 1. If the
stem already exists (two scans in the same second) it gets a suffix `-2`, `-3`,
and so on, so the PDF and the images of one scan always match by name.

Gallery copies are optional and off by default, with an explanation of what
sharing to the Gallery implies. The switch only adds one extra copy in the
Gallery; it does not change where the originals are stored. The e-mail contains
only the PDF.

## ADR-008 Scan without JSON
Scan does not generate JSON. The Budget app reads the PDFs directly. The
JSON contract (`DATA_CONTRACT_V1.md`) is kept as history only and is marked
superseded: `schemaVersion`, `documentId` and `documentType` are cancelled. The
Receipt/Document choice and the soft filter existed for the JSON export and are
suspended (open, decided in the OCR phase). Open question, decided in the PDF
phase: either the Scan PDF has an invisible text layer (searchable PDF) or
Budget does its own OCR. ADR-003 is unchanged: the apps stay independent.

## ADR-006 Sending model
Direct sending from the app (one click) with a configurable sending account that
may differ from the device account. Provider abstraction (`MailProvider`) with
Gmail, Outlook and Yahoo. Authentication approach decided at the start of the
mail phase. If OCR yields no text, the mail is still sent with the PDF and the
user is notified.

## ADR-007 Hand-written localization
EL/EN strings are an abstract class with two implementations, so a missing
translation is a compile error. Can move to ARB later.

## ADR-009 Names of the Gallery copies, app icon, splash
The optional Gallery copy is named `scan_YYYY-MM-DD_NN.jpg`:

- Prefix `scan_` makes the copies easy to filter in the Gallery. The date is
  the device date, without the time.
- `NN` is a **daily counter**, two digits with a leading zero (`01`, `02`...)
  and no limit at 99 (`100`, `101`...). Every image copied to the Gallery takes
  the next number of the day, so a multi-page scan uses consecutive numbers.
  A new device date starts again at 1.
- The counter advances only after a copy was saved, so failures leave no gap,
  and with the Gallery switch off no number is used. The date and the last
  number live in the key/value store (`gallery.counter.date`,
  `gallery.counter.last`).
- The files in `./pictures/` keep their own names (`<stem>_<n>.jpg`, ADR-005).
- Technically: `gal` names the copy after the file it is given, so the picture
  is first copied under the wanted name into the app cache
  (`gallery_copies/`), handed to `gal` and deleted again; leftovers are purged
  at start-up. The counter is a port (`GalleryCounterStore`), the naming a pure
  class (`GalleryNaming`, injected clock).
- Known limit: if the app data is cleared the counter restarts at 1 while
  older `scan_<date>_01.jpg` copies may still exist; Android then adds its own
  suffix to the new file name instead of overwriting.

App icon and splash are generated from two source images in `assets/branding/`
by `tool/generate_branding.dart` (dev dependency `image`, pure Dart), and the
generated files are committed:

- Adaptive icon: the symbol is keyed out of the green image (spill
  `G - max(R, B)`: background from 110, symbol up to 30, linear between; green
  removed from soft edges), scaled so the smallest circle around its opaque
  pixels fits the 66dp safe zone of the 108dp canvas, on a radial-gradient
  background drawn as a vector (no image) with the colours of the original
  plate. Legacy icon (Android 7.x): the original image.
- Splash: the original icon, scaled so the whole plate sits inside the 192dp
  circle that Android 12+ masks the icon with, on the colour of the frame
  around the plate (same in light and dark mode). Before Android 12 the same
  image is centred by `launch_background`. No splash package is used.
- Out of scope: monochrome (themed) icon.


## ADR-010 OCR engine: Paddle only, behind `OcrEngine`
Scan reads text with PaddleOCR PP-OCRv5 (detection + recognition, ONNX
Runtime through `flutter_onnxruntime`). No ML Kit (no Greek, and it crashed
under R8 in the spike) and no Tesseract (does not build with the current Gradle
template, and it ignores the EXIF orientation). The domain only knows the port
`OcrEngine` (`domain/ports/ocr_engine.dart`), so the engine can be replaced
without touching the use cases or the UI.

The run configuration comes from the phone measurements of Phase 1.6 to 1.6c
and lives in one place, `OcrConfig` (no magic numbers elsewhere):

- provider CPU, recognition batch 1 (batch 4 or 8 was 40% to 70% slower on the
  phone), detection side 960 (peak memory about 616 MB; 1280 gave about
  1031 MB), 4 threads (the spike default; the thread grid on the phone is not
  finished);
- the stock recognition model, not the ArgMax derivative: it was about 6%
  slower on the phone and saved only about 250 ms of CTC decoding, which typed
  loops in Dart do in about 70 ms. Models stay exactly as their source
  publishes them (one hash each);
- XNNPACK and NNAPI are not used: they did not beat the noise on the phone and
  the accuracy check on the phone was never made;
- the engine lives in one long-lived background isolate with the models loaded
  once. On the phone this does not make the reading faster, but it keeps the UI
  isolate free (a stall of about 20 ms against 125 to 150 ms);
- the page timeout is 45 s and the result is a sealed type (`success`,
  `timedOut`, `failed(reason)`, `cancelled`), never an exception to the UI.

## ADR-011 Language packs per script, chosen by the user
A pack is one recognition model with its dictionary; the detector is shared.
Two packs are bundled: `greek` (Greek and English, about 7.8 MB) and `latin`
(English and the Latin-script languages with accents, about 7.9 MB). The
choice is explicit and visible in Settings; the app never detects the language,
because a wrong pack fails badly (mixed Greek and English: Greek pack CER 2.9%,
Latin pack 26%; accented lines: Greek pack 0 of 284 accented letters, Latin pack
284 of 284; see `OCR_LANGUAGE_PACKS.md`).

First run: `greek` when the device language is Greek, `latin` otherwise. The
choice is stored in the key/value store (`settings.ocr.pack`); the first-run
wizard is unchanged. The registry (`OcrLanguagePackRegistry`) describes packs
with an availability (`bundled` or `downloadable`) so that packs outside the APK
(ru and others) fit later; downloading is future work and there is no network
code in the OCR layer. Packs not in the APK must be fetched from our own hosting
with a pinned SHA-256 (see the open item in `THIRD_PARTY_NOTICES.md`).

## ADR-012 The OCR sits on the SCAN & SEND path
The PDF of Phase 3 is meant to be searchable (an invisible text layer), so the
text and its geometry are needed while the document is made, not afterwards.
That is why the OCR result carries four corner points per line, normalised to
the upright working image, and why the reading of each page starts as soon as
the page is shot (Multi Page: the next page is photographed while the previous
one is read). Per-character boxes (`charBoxes`) stay empty in Phase 2: Phase
2.1 decides, on the phone, whether the selection and copying of a code such as
an RF code needs them. The text screen of Phase 2 is a check tool, not the final
UX (the final flow is one click with no text screen).

Update (Phase 3): Phase 2.1 found that per-word pieces need the place of the
characters, so the engine now fills `charBoxes` from the CTC time steps
(ADR-016).

## ADR-013 The scanner never changes the text it reads
No correction of look-alike letters (Greek and Latin), no spell checking, no
normalisation. The only thing allowed is to flag lines of low confidence
(handwriting that comes out as rubbish): below `OcrConfig.minLineConfidence` the
line is marked `filtered`. The result keeps every raw line and the flag; only
the visible text leaves the flagged lines out. The threshold is 0.65 (user
decision after the first phone check; first version 0.5, PaddleOCR's own
`drop_score`). Observed: pen strokes that are not text scored 0.38 to 0.60, clean,
blurred and faint printed text 0.96 to 1.00 (invented pages; measurements in
`PHASE_2_VALIDATION.md`). The check screen counts the "borderline" lines
(0.50 to 0.65) so the effect on real documents can be judged. Threads stay at
4: more do not help on the phone's small cores. Any matching that must tolerate look-alike letters
belongs to the consumer (Budget normalises text already).

## ADR-014 Image decode policy
- Never decode on the UI isolate. The 200 MP photo of Phase 1.6c froze the UI
  for about 8 s per Dart decode and ended in the "not responding" dialog.
- The header is read first (JPEG SOF or PNG IHDR, a few small reads) and gives
  the size without decoding anything.
- Up to 8 MP: `package:image` in a background isolate. Above 8 MP: native
  decode in Kotlin (`ImageDecodeHandler`), with `inSampleSize` so the
  full-size bitmap is never created (the bitmap is at most about 5120 x 5120,
  105 MB, whatever the file size), then rotation and scaling in one pass.
  The 50 MP limit is the limit of a FULL decode, which never happens above it.
  First version of this ADR (phase 2) refused everything above 50 MP; the
  first phone check (camera 3060 x 4080, 12.5 MP) and the Phase 1.6c data (200 MP
  sample: native decode 130 to 330 ms, peak memory about 500 MB) showed that
  was too strict.
- Ceiling: a header above 400 MP (`OcrConfig.maxMegapixels`, twice the largest
  sensor mode seen) or an unreadable header fails with `imageTooLarge` or
  `imageUnreadable`; a file the native decoder cannot read fails as
  `imageUnreadable`. In all cases nothing crashes and the scan is still saved.
  The limits are inclusive.
- The result is the upright working copy: EXIF orientation applied (the invalid
  value 0, and anything outside 1 to 8, mean no rotation), long side at most
  2560, JPEG quality 95, in the app cache (`ocr_work/`, purged at start-up).
  The PDF of Phase 3 will use the same file.
- Sizes are the pixels of the decoded image and the header's SOF size, never
  `ExifImageWidth/Height` (false on Xiaomi camera files: 1840x4080 for a
  972x1260 file).
- One image at a time, buffers released after each page, models released when
  the result screen is left.

## ADR-015 The PDF is named after the pictures and stored in `./pdf`
A scan makes one PDF, for one page or for many (a Multi Page scan is one PDF
with N pages, never N PDFs). It is stored in `./pdf/` of the folder the user
chose (ADR-005), as `<stem>.pdf`, with the **stem of the pictures of the same
scan**: `pdf/2026-10-21_19-05-12.pdf` next to
`pictures/2026-10-21_19-05-12_1.jpg`, `..._2.jpg`. For a Multi Page scan the
stem is the one of the first page, which is the stem of all of them.

- The request for this phase spoke of the `scan_YYYY-MM-DD_NN` name of ADR-009.
  That name belongs only to the optional **Gallery copy** (a counter that
  advances only when the Gallery switch is on), not to the files in
  `./pictures`, so it could not name the PDF without changing ADR-009 and
  ADR-005. The user confirmed the ADR-005 name.
- No collision is possible in the normal flow: `StoreScanPages` picks the stem
  that is free in **both** `./pictures` and `./pdf` (`-2`, `-3` on a clash,
  e.g. a PDF left behind after the user deleted the pictures), so a PDF always
  matches its pictures by name. If a file with the PDF's name shows up between
  the listing and the copy (two scans in the same second) the copy fails with
  `exists` instead of replacing it, and `StoreScanPdf` tries the next free name
  (`-2`, ...). A file in the user's folder is never replaced.
- The photos are stored first and are never touched by the PDF step. A PDF that
  cannot be written (no access, full storage, folder gone) is a message on the
  result screen with a Try again button; the photos stay.
- The stored file is handed to the viewer by its document URI
  (`ScanFileStore.copyToFolder` now returns it) with `ACTION_VIEW` and a
  temporary read grant (`ScanFilesHandler.openDocument`).

## ADR-016 The text layer is a best effort, one hidden piece per word
The product is the PDF made from what the camera sees. The invisible text
under the picture (search and selection in a viewer) is a **free extra**, not a
promise: nothing in the app or in the documents says that copying is exact, the
result screen says the opposite ("read automatically, can contain mistakes,
check the document"), and if the OCR fails, times out or is cancelled the PDF
is still made, with the picture only.

- Layout: one piece of hidden text **per word** (text render mode 3), the
  variant of Phase 2.1 that worked in the Google Drive viewer
  (`PDF_SPIKE_RESULTS.md`): per word the selection of an RF code or an IBAN was
  exact in the viewer, per line it was not reliable and per character it was
  worse. A word is cut from the line at its spaces and takes the place of **its
  own characters**.
- Character places come from the CTC time steps of the recognition model
  (`OcrLine.charBoxes`): the centre of a character is the middle of the time
  steps of its run, the edge between two characters is the midpoint of their
  centres. No extra inference. A line whose boxes are missing, or do not add up
  to its text, becomes one piece for the whole line (a degradation, not a
  failure).
- Font: Noto Sans Regular (SIL Open Font License 1.1) through the `pdf` package
  (Apache-2.0), which embeds only the glyphs that are used (a few KB per page)
  and writes a `ToUnicode` map. Not the "glyphless" writer of the spike: it is
  our own code to keep for a small gain; it stays in the backlog. The font
  covers every Latin and Greek letter, digit and punctuation mark of both
  dictionaries; mathematical symbols, arrows and Roman-numeral glyphs are not in
  the font and are left out of the hidden text.
- Which lines: only those that passed the confidence filter (0.65, ADR-013).
  Lines below it are not written. Control and zero-width characters are left
  out. The text itself is never changed (ADR-013).
- Time: the PDF is written in a background isolate (40 to 430 ms on the
  emulator for 1 to 3 pages, layout and isolate start included) once every page
  has an outcome: the OCR of the pages is
  pipelined while the user shoots, and each page has the 45 s limit (ADR-010).
  "Create the PDF without waiting for the text" stops the reading and makes the
  PDF with no text for the pages not read yet.
- Check digits of RF and IBAN codes (mod 97), per-character layout and the
  glyphless writer are **frozen** in the backlog until users ask for them.

## ADR-017 The picture of the PDF is the working copy; the page follows the pixels
The picture of every page is the **upright working copy** of Phase 2 (ADR-014):
EXIF orientation applied, long side at most 2560 px, JPEG quality 95, no EXIF,
no GPS. A JPEG goes into the PDF as it is, without a new compression (a test
finds the bytes of the file inside the PDF). The PDF therefore carries no
location, no camera data and no personal data: no author, producer, title or
date either (a test reads the bytes); the only thing about the library is the
comment line it writes in the header, and the trailer has a random document ID.

The size of a page is `pixels * 72 / 200` points: a constant of **200 dpi**
(`PdfConfig.dpi`). Reason: the ratio of the page is exactly the ratio of the
picture, so nothing is stretched, whatever the shape of the paper or the way
the phone was held; 200 dpi puts a 2560 px page at about 12.8 in on its long
side (A4 is 11.7 in at 219 dpi), which every viewer fits to the screen, and
the size of the file depends on the pixels only, not on the page size, so the
page size has no effect on the limits of e-mail attachments.

If a photo's working copy could not be made (unreadable file, over 400 MP) there
is no picture for that page and the PDF is not made; the message says so and the
photos are saved.

## ADR-018 No picture of the user stays in the cache
The working copies live in the app cache (`ocr_work/`) and the PDF in
`pdf_work/` only as long as they are needed:

- the PDF in the cache is deleted as soon as it is copied to `./pdf` (also when
  the copy fails);
- the working copies are deleted when the PDF is **stored**
  (`OcrSession.releaseWorkingCopies`), not when the result screen is left. The
  results of the reading stay in memory for the OCR check screen; its "show
  boxes" switch then draws on the shot in the cache (`scan_pages/`, which stays
  until the result screen is left, as before; the boxes are fractions of the
  upright picture, so they fit it);
- when the PDF fails the copies are kept for "Try again" and are deleted when
  the screen is left (as before); when the scan is abandoned they are deleted
  with it;
- both folders are purged at start-up, for a run that was killed half way.

While the PDF is made the result screen cannot be left (the buttons and the
system back are off), because leaving ends the reading and deletes the working
copies; the wait is bounded by the 45 s limit per page.

## ADR-019 `MailProvider` with several ways to sign in; app password now, OAuth for the public release
The mail layer is a port, `MailSender` (`domain/ports/mail_sender.dart`), that
takes a `MailMessage`, a `MailAuth` and a `MailProvider` and answers with a
sealed `MailOutcome` (`MailSent`, `MailAuthFailed`, `MailNetworkError`,
`MailTooLarge`, `MailRejected(code)`, `MailCancelled`, `MailUnknown`, and
`MailNotConfigured`, added because the use case checks the settings before it
tries anything). It never throws to the UI and no outcome carries an address, a
password or the text of a server reply.

- `MailProvider` (`domain/mail/`) is a plain value: SMTP host, port and
  security (implicit TLS or STARTTLS), the kinds of sign-in it supports
  (`MailAuthKind.appPassword` today, `oauth` later), whether app passwords are
  confirmed to work (`AppPasswordSupport`) and the biggest message it takes.
  `MailProviderRegistry.standard` maps `MailProviderId` (`gmail`, `outlook`,
  `yahoo`) to the facts of `MAIL_PROVIDERS.md`.
- `MailAuth` is sealed. `AppPasswordAuth` exists; `OAuthAuth` is reserved. A
  sender switches over the sealed type, so adding OAuth is a new subclass, a new
  case in a sender and a new implementation, and no change in the use cases, the
  cubits or the screens (`MAIL_OAUTH_PLAN.md`).
- The development and the first versions use **SMTP with an app password**
  (Gmail, Outlook.com, Yahoo), with the share route as the way out. The final
  public version moves to OAuth (Google `gmail.send`, Microsoft Graph or SMTP
  XOAUTH2); the milestone is "Phase 8: Mail OAuth and public release readiness"
  in the roadmap and its long-lead tasks (package id, signing key, privacy
  policy, Google verification) should start early.
- **The library is `mailer` 7.2.0** (MIT), not `enough_mail` (MPL-2.0, which asks
  that changes to its files are published, and which is an IMAP/POP/SMTP client
  far bigger than what is needed). Reasons from the packages themselves:
  `mailer` is SMTP only; `ssl: false` upgrades the connection with STARTTLS and
  aborts if the server does not offer it (`allowInsecure` false), `ssl: true` is
  implicit TLS; it streams a file attachment from disk and uses CHUNKING when
  the server offers it; it has AUTH PLAIN, LOGIN and XOAUTH2 (the last is what
  the OAuth phase needs); a `timeout` for every wait of the server; its errors
  are a small set of exception classes that `smtp_error_mapping.dart` turns into
  outcomes (535 and the other sign-in replies to `authFailed`, 552 to
  `tooLarge`, a socket, timeout or TLS error to `network`, any other reply to
  `rejected(code)`). It builds the whole message by streaming, with no extra
  dependency of weight (`mime`, `path`, `logging`, `async`, `punycoder`,
  `unorm_dart`). Its error text can hold the reply of the server, which can hold
  the address of the user, so the code reads only the 3 digit reply code and
  throws the text away.
- The send runs in **its own isolate** (`SmtpMailSender` and `smtp_worker.dart`):
  the file is read and encoded off the UI isolate, and a cancel kills the
  isolate, which closes the connection. A message is delivered only if the
  server received all of it, so a cancel never delivers a half message.
  Timeouts: 30 s for each reply of the server, 4 minutes for the whole send,
  3 times the reply limit for a connection test.
- The test provider `testLocal` (plain connection to a server on the PC) is
  **not in the app**: `MailProviderRegistry` takes its map in the constructor
  and only tests build one (`test/support/mail_fakes.dart`); a test checks that
  the standard registry holds exactly `gmail`, `outlook` and `yahoo`.

## ADR-020 The subject is "One Click Scan - <name of the PDF>", the body is neutral, no OCR text
The mail has one attachment, the PDF, a **subject** `One Click Scan - 2026-10-21_19-05-12`
(the fixed words, then the name of the PDF without `.pdf`, which is the stem of
the scan with `-2`, `-3` on a collision) and a **body** of one fixed line in the
language of the app (`Σαρωμένο έγγραφο από το One Click Scan.` or `Document
scanned with One Click Scan.`). No text of the document is ever in the mail.

- The fixed start of the subject is a user decision: the user can make one rule
  in their mail app (subject starts with "One Click Scan") and forward all scans
  to a folder, without a rule on the sender, which would be the user's own
  address. The part after it keeps every subject unique and equal to the name of
  the file.
- This replaces the earlier text of ADR-005 and of the architecture, that the
  subject is the bare stem. The stem of the file names is unchanged.
- `MailText` (`domain/mail/mail_text.dart`) builds both texts, so there is one
  place to change them.

## ADR-021 The password is in the Android Keystore, outside backups, outside logs
The app password is stored with `flutter_secure_storage` 11.2.0 (BSD-3-Clause;
Android Keystore: a Keystore key wraps the storage key, AES-GCM encrypts the
value), behind the port `MailCredentialStore` and the adapter
`SecureMailCredentialStore`.

- **One value** under one fixed key (`mail.credentials.v1`): provider, account
  and password together as JSON, so the account is not in the clear in a key
  name, and a password is only used for the provider and the account it was
  stored for (`StoredMailSecret.belongsTo`). One account at a time.
- It is **never in the key/value store** (`shared_preferences`): a test checks the
  settings keys and values. The integration test writes a canary password and
  reads every file of the app's private folder outside the cache: none holds it
  in the clear.
- **Not in backups.** The manifest has `android:allowBackup="false"`,
  `fullBackupContent="false"` and `dataExtractionRules` that exclude every domain
  for cloud backup and device transfer (the plugin's README asks for the first,
  because a restored ciphertext without its Keystore key cannot be opened).
  Side effect: the settings are not backed up either; the user sets the app up
  again on a new phone, which is the safer choice for an app with a password.
  A password that cannot be read (for example a lost key) is the same as no
  password: the user enters it again.
- **Not in logs.** Nothing logs an address, a subject, a password or a server
  reply; the places that log an error log its type only. `AppPasswordAuth`,
  `StoredMailSecret`, `MailMessage` and `SettingsEditorState` print as
  `<redacted>`. A canary password goes through the whole flow in unit tests (a
  logger that keeps the error as well) and in the integration test, and is
  looked for in every log line.
- The field is hidden with a button that shows it, with no suggestions or
  autocorrect, and the typed password lives only in the field and in the cubit
  until Save writes it; Save clears it. "Delete the stored password" removes it.
- The permission is `INTERNET`, and no network-state permission: the only code
  that uses the network is `lib/services/mail/` (a test reads the sources).

## ADR-022 Two ways to send: `sendNow` and `shareDraft`
`MailSendMode.sendNow` (default) sends from the app over SMTP. `shareDraft` opens
the e-mail app of the user (`ACTION_SEND`, `EXTRA_EMAIL`, `EXTRA_SUBJECT`,
`EXTRA_TEXT`, and the PDF as `EXTRA_STREAM`, the `content://` document URI of
the stored file with `FLAG_GRANT_READ_URI_PERMISSION` on the intent and on its
`ClipData`, read only), and **the user presses send there**; the app cannot know
whether that happens. The mode is a setting saved at once. After a failed send
"Open in the e-mail app" is offered on the result screen, whatever the mode.

- Kotlin: `ScanFilesHandler.kt` got `shareDocument`, `describeShare` (the same
  function builds the intent, and the answer is what the intent carries, for the
  tests) and `copyUriToFile` (native copy of the stored PDF into the app cache, so
  the SMTP sender can read it; bytes never cross the channel; the copy is
  deleted after the send and purged at start-up).
- Outlook.com: the Settings screen says up front that an app password is not
  confirmed to work (`MAIL_PROVIDERS.md`), and a refused password adds the same
  warning and the share route on the result screen.

## ADR-023 Sending is a tap in Phase 4; the automatic send comes with the one-click phase
The result screen has a **Send** button after the PDF is stored (idle: where
the PDF goes; sending: a state in words and a Cancel button, no spinner; sent:
"The message was sent from the e-mail server."; failed: why, Try again, Open in
the e-mail app; no account or password: a button to Settings). The text never
promises delivery, only what is known: the server accepted the message.

- No automatic send and **no automatic retry** (Auto Retry is V1.5). Leaving the
  screen is locked while a send runs (the Cancel button is the way out).
- The settings are read at each tap, so an account set up in Settings a moment
  ago is used.
- A PDF over the limit of the provider is refused **before** it is read or sent
  (`MailSizePolicy`: the limit of the message divided by 1.37 for the MIME
  encoding, minus room for the headers; about 18.2 MB of PDF for Gmail and 14.6 MB
  for Outlook.com and Yahoo, `MAIL_PROVIDERS.md`), with the share route as the
  way out. A server reply 552 gives the same message.
- The one-click flow (a scan that sends by itself, with an empty OCR still sent)
  is the one-click phase of the roadmap (Phase 5 in `ROADMAP.md`; the request
  for Phase 4 called it Phase 7, where the table has "Revisit the Budget
  integration"). The button of this phase is the part of it that exists now.
