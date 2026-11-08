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

## ADR-024 The share route opens the provider's own e-mail app first; a failed sign-in has a one-tap way out; the guide opens the provider's page
Phase 4 opened the generic Android share menu for the e-mail route. The user's
check on a phone showed that the route works (Gmail got the mail with the subject,
the body and the PDF), and asked for the e-mail app to open directly.

- **Order** (`chooseShareRoute`, pure, `domain/mail/share_route.dart`): (1) the
  installed app of the provider chosen in Settings, by an explicit intent with
  `setPackage`, so the compose screen opens at once; (2) otherwise the apps that
  handle `ACTION_SENDTO` with `mailto:`: one is opened directly, several are shown
  in a chooser that lists only them (the first is the target, the others its
  `EXTRA_INITIAL_INTENTS`); (3) only when there is no e-mail app, the generic share
  menu, and the screen says that no e-mail app was found (`openedGeneric`).
  Dart decides (`ShareScanPdfDraft` asks a `MailAppFinder`), Kotlin carries out
  (`findMailApps`, `shareDocument`), so the choice is a unit test with a fake phone.
- **The PDF**: `content://` document URI, `FLAG_GRANT_READ_URI_PERMISSION` on the
  intent and the ClipData, and `grantUriPermission` for the chosen package, read
  only, never write. The target app's real ability to read it is a phone check.
- **Package visibility** (Android 11 and newer): `<queries>` with the three
  package names and one `mailto` intent; no `QUERY_ALL_PACKAGES`. The package
  names are not confirmed from an official page (`MAIL_PROVIDERS.md`); the install
  check and the fallback make a wrong name harmless.
- **The account** is the one the e-mail app has selected; the app cannot choose
  it. The share texts say so (EL and EN).
- **Diagnostic line** on a failed test or send: the step and the reply code,
  nothing else (`MailOutcome.stage`, `MailOutcome.replyCode`). The isolate sends
  back a tag, a code and a step index, never text. A canary test checks that no
  password or address gets in.
- **One-tap backup way**: when the sign-in is refused, or the provider is Outlook
  (no app password for SMTP), and the mode is `sendNow`, the screen shows the reason
  and a button that sets the mode to `shareDraft` (the same setting as in
  Settings, `MailSendCubit.useShareMode`). Not shown when the mode is already
  `shareDraft`. The refused-sign-in text now says that with MFA an app password
  made at the provider is needed, not the normal password, and that an
  administrator may forbid app passwords.
- **Guide per provider** in Settings (what an app password is, prerequisites,
  numbered steps, a reminder, a button). Gmail and Yahoo open the official page in
  the browser; Outlook has no steps, only that it waits for OAuth. Menu names are
  used only where an official page gave them (Yahoo); for Gmail only the address.
  The wizard of the first run is **not** changed: it has no password field, and
  the guide is in Settings (a one-line note in the plan of Phase 4.1).
- **Opening a link** is `ACTION_VIEW` through the existing channel
  (`ScanFilesHandler.kt`, `openLink`), with no new package, only on a tap, and
  only for a link that the registry allows (`MailProviderRegistry.isAllowedGuideLink`:
  `https`, no user info, no query, no fragment, exactly a guide page of a
  provider; the Kotlin side again accepts only `https`). Nothing of the user goes
  into the link. This starts the browser; the app itself opens no connection and
  uses no socket, so `no_network_test.dart` still holds (it now also checks that
  there is no `url_launcher` and that only the native link opener sends
  `openLink`).

## ADR-025 One Click or preview: a choice of the user, made in the wizard; the flow after the capture is one use case
Phase 5 connects the pieces of Phases 1 to 4 into one flow. Two ways exist and
the user chooses (`ScanFlowMode`: `oneClick`, `preview`).

- **One Click:** the scan is stored, read, made into a PDF and delivered by the
  mode of Settings (`sendNow` or `shareDraft`, ADR-022) with no further tap. There
  is no preview. In `shareDraft` the e-mail app opens at once (ADR-024).
- **Preview:** the flow stops once the PDF is stored. The screen shows the pages
  (thumbnails), the PDF (open it), **Send** and **Discard**. Send is the manual send
  of Phase 4 (`MailSendCubit`).
- **The choice** is `AppSettings.scanFlowMode`, nullable, key
  `settings.scan.flowMode`. The wizard has a **new last step** with an
  explanation and two options, **no default**, and "Next" disabled until one is
  chosen; `firstRunCompleted` is now set by that step, not by the Gallery step (the
  existing steps are unchanged otherwise). Settings has a switch "One Click mode
  (no preview)" with the same explanation, saved at once.
- **Installs from before Phase 5** never saw the step and have no value. Null means
  the **preview** (`effectiveScanFlowMode`); the Settings switch shows off. The
  user keeps seeing the pages first until they choose. A test reads an old store.
- **Where the flow lives.** `ScanAndSend` (`domain/usecases/scan_and_send.dart`)
  takes over after the pictures are stored: wait for the text of every page, make
  and store the PDF (`StoreScanPdf`), then in One Click deliver (`SendScanPdf` or
  `ShareScanPdfDraft`). It returns a stream of sealed `ScanFlowState`
  (`FlowRecognizing`, `FlowBuildingPdf`, `FlowAwaitingDecision`, `FlowSending`,
  `FlowSharing`, and the final `FlowFinished`, `FlowPdfFailed`, `FlowCancelled`) and
  never throws. `ScanFlowCubit` shows the states and starts what the user asks
  for; the widgets hold no flow logic.
  **Deviation from the request:** capturing and storing stay in `ScanCubit`
  (camera, retry of a failed save, rollback), where they already were. They are its
  states `capturing` and `saving`, shown before the flow starts. Pulling them into
  the use case would have moved the camera port into `domain/` for no gain.
- **Single and Multi.** Single: the shot starts the flow. Multi: the scan goes on
  page by page (the OCR of each page already runs while the next is shot) and
  "Done" starts the flow.
- **Progress** is text of the stage and a bar that moves when a page is done, no
  spinner that runs all the time (Phase 2 measured that an animation slows the
  OCR).
- **Manual actions stay manual.** A mail that did not leave is retried by the
  user's tap (`MailSendCubit`, which takes over the result with `adopt`), never
  by the app on its own, and nothing is queued (V1.5).

## ADR-026 What each stage leaves on the disk when it fails, and how the flow stops
The rule: **a scan is never lost because of a later stage.** The pictures are
stored before anything else; nothing after them deletes them.

| Stage | If it fails or is cancelled | On the disk | The screen says |
|---|---|---|---|
| Capture | Nothing is stored yet; the shots stay in the cache | cache only | the camera screen as before (retry, or discard with a question) |
| Store the pictures | All or nothing: written pictures are rolled back | nothing | "could not be saved, kept for a retry" (Phase 1) |
| OCR of a page: failed, or the 45 s limit | The page goes in **without text**; the flow goes on | pictures, PDF | "N pages without text" |
| Reading, cancelled by the user | The pages not read are cancelled; **no PDF is made** | pictures | "Cancelled. The pictures are saved. No PDF was made." |
| Make or store the PDF | `FlowPdfFailed(reason)`; the readings are kept, "Try again" repeats only the PDF | pictures | the reason and "Try again" |
| Settings or password missing | The PDF is stored; the mail is not tried | pictures, PDF | "Not sent", the way to Settings |
| Sending: no network, refused, too large | `DeliveryNotSent`; **no automatic retry** | pictures, PDF | "Not sent", the reason, "Try again", the backup way |
| Sending, cancelled by the user | The send stops | pictures, PDF | "Cancelled. Saved. Nothing was sent." and the manual Send |
| `shareDraft`: no e-mail app, or a failed hand-over | `DeliveryShared(result)` with the result | pictures, PDF | the text of that result |
| Gallery copy | Never fails the scan (Phase 1) | pictures, PDF | "Gallery copy failed" on the picture |

- **Cancel** exists while the text is read and while the mail is sent, as an
  explicit button. *(Phase 5.1, ADR-028: it now exists in every stage, also while
  the pictures are written and while the PDF is made, and Back asks and then
  cancels.)* Leaving the screen is locked while work runs (`PopScope`).
- **The app is killed inside the flow.** Nothing is solved here. The user finds the
  pictures stored (they were first), no PDF if it was not made yet, and the mail not
  sent. The cache is purged at the next start. The repeat is by hand: scan again, or
  use the pictures. A stored PDF is already in `./pdf`.

## ADR-027 Discard deletes only what the scan created, by recorded URI, and says what is left
"Discard" (preview only) deletes the whole scan after a question that says the
deletion cannot be undone.

- **By URI only, never by name or by folder.** `StoredPicture.uri` (document URI
  of the picture in `./pictures`, which `copyToFolder` already returned and
  `StoreScanPages` threw away), `StoredPdf.uri`, and `StoredPicture.galleryUri` are
  recorded when the files are written. `DiscardScan` deletes exactly those.
  Another scan of the user, in the same folders, cannot be touched. A picture
  without a recorded URI counts as **left**, it is not searched for.
- **Deleting a document** (`ScanFileStore.deleteByUri`, Kotlin `deleteDocument`):
  only a URI under a folder the user granted (`persistedUriPermissions`); a missing
  document counts as deleted; any other failure is an error.
- **Gallery.** The plugin `gal` returns no URI, so the Gallery copy is now written
  by `ScanFilesHandler.kt` into MediaStore (`Pictures/`, pending while written) and
  its URI is returned; `GalleryService.deleteImage(uri)` deletes that one entry.
  `gal` stays for one thing only, the storage permission that Android 9 and older
  need (it asks only when a copy is requested, as before). **No new permission**:
  `WRITE_EXTERNAL_STORAGE` was already declared for Android 10 and older.
- **What the Android documentation says** (checked 2026-10-27,
  <https://developer.android.com/training/data-storage/shared/media>): from
  Android 10 an app needs no storage permission to access and modify media files
  **it owns**; to delete files of **other apps** the user has to agree
  (`MediaStore.createDeleteRequest`). The page does not say in so many words that
  `ContentResolver.delete()` of an owned entry succeeds with no checks. **Seen on the
  emulator (Android 16, 2026-10-28):** deleting an entry the app created works with
  no permission (`one_click_flow_test`, preview and Discard, `gallery_copy_test`).
  Deleting an entry that is already gone does **not** return zero rows there, it
  throws `SecurityException`, so `deleteGalleryItem` checks whether the entry still
  exists and counts a missing one as deleted (a retry of Discard must not stay
  "left" for ever). **Not yet seen on a real phone**, see `PHASE_5_VALIDATION.md`. A Gallery
  entry written by an earlier install of the app may belong to nobody the app
  can delete for; then the outcome counts it as left, and the screen says so.
- **The outcome counts what is left per category** (`DiscardOutcome`: pictures,
  PDF, Gallery copies). The screen says "The scan was deleted" **only when all
  three are zero**; otherwise it names what stayed and the Discard button stays, so
  the user can try again (deleting what is already gone is not an error).
- **Not offered after the choice is made:** once the message is sent, being sent,
  or the e-mail app got the PDF, Discard disappears. In One Click there is no Discard.

## ADR-028 Cancel in every stage, Back is Cancel, and the screen goes home by itself after a sent message (Phase 5.1)
The phone check of Phase 5 found that between "Done" and the send there was no way
to stop (21 shots: writing the pictures, the reading and the PDF had no button, and
the Back arrow did nothing, without a word). This replaces the line of ADR-026 that
said Cancel "does not exist while the PDF is written".

**What each control does, by stage** (found in the code before the change):

| Stage | Back arrow / system Back | Undo arrow | Cancel button |
|---|---|---|---|
| Shooting (Single or Multi) | Asks "Stay / Discard" when there are shots (they are only in the cache, so Discard really deletes them); leaves at once with none | on in Multi when ready, off while a shot is taken | none needed |
| Writing the pictures (after "Done", or the shot in Single) | **before:** ignored in silence. **now:** asks "Stop the processing?" and then stops | off (it is not in the screen's `ready` phase) | **new** |
| Reading the text (OCR) | **before:** ignored in silence. **now:** same question, then Cancel | gone (the camera screen is left) | existed |
| Making the PDF | **before:** ignored in silence. **now:** same question, then Cancel | gone | **new** |
| Sending (One Click, or the Send of the preview) | **before:** ignored in silence. **now:** same question, then Cancel | gone | existed |
| Preview, or the end | leaves, no question (nothing runs; the scan stays saved) | gone | none |

**The two questions are different and the texts say so.** While shooting, "Discard"
deletes shots that were never saved. After "Done" the pictures are in the folder, so
"Stop the processing?" says what stays (the texts are in `AppStrings`, `stopBody*`).
Pictures are written at "Done" (in Single, right after the shot), never during the
shooting.

**What stopping leaves (decided with the user, 2026-10-28):**
- *While the pictures are written:* **rollback, back to the camera.** The store was
  already all-or-nothing (ADR-026); a cancel is treated like a failure. It stops
  between two pictures, deletes the pictures and the Gallery copies written so far
  (by name and by recorded URI), throws `ScanStoreCancelled`. The shots stay in the
  cache; in Multi the screen returns to the camera with the shots ("Saving stopped.
  Nothing was saved and your shots are still here."); in Single the one shot is
  dropped (it was taken only to be saved) and the message says so. No half scan is
  ever left. This differs from the first idea of the request ("pictures already
  stored stay"), because a scan with 7 of 21 pages is worse than none.
- *While the text is read:* the pictures stay (folder and Gallery), no PDF, nothing
  sent. "Processing stopped. The photos are saved, no PDF was made." and one tap
  home. The reading stops at once through the existing cancel of the session.
- *While the PDF is made:* the screen stops at once (`FlowCancelled(buildingPdf)`);
  the writer (an isolate of the PDF plugin) **cannot be interrupted**, so
  `ScanAndSend` waits for it in the background, and what it finishes is deleted by
  its URI (`ScanFileStore.deleteByUri`); the cache copy is already deleted by
  `StoreScanPdf`. The stream ends only after that clean-up. A writer that fails
  after the stop leaves nothing. A PDF is never left without a finished scan, and no
  `.tmp` stays. If the app is killed in that short time the PDF can remain; this is
  the same "killed inside the flow" case of ADR-026.
- *While sending:* as in ADR-026 (scan and PDF saved, nothing sent, manual Send).

**Back is Cancel.** The Back arrow and the system Back (`PopScope`) ask once, "Stop
the processing?" with "Continue" and "Stop", and "Stop" does exactly what the Cancel
button does. They never leave, or stop, in silence. The existing question while
shooting is unchanged.

**After Discard** the preview's own parts disappear (the "Check the scan" text, the
Send section) after any discard attempt. One state decides it (`discard == done`).
In a *partial* discard the "Discard" button stays, as the way to try again (ADR-027).
(The request asked that it go too; it is kept because without it the leftovers could
not be removed from the screen. Say so if you want it hidden.)

**Automatic return.** After a message that really left (`MailPhase.sent`: One Click,
or the Send of the preview, or its retry) the result screen counts down from
`autoReturnSeconds` (10, one constant in `auto_return_cubit.dart`) with "Back to home
in N s" and goes home at zero. **Any touch** stops the count for good (a `Listener` at
the top of the screen); the "Back to home" button is the manual way out. Not
started when the send failed, when only the e-mail app was opened (`shareDraft`), or
while anything runs. One update a second, no animation. `AutoReturnCubit` takes the
clock as an injected stream so a test drives time by hand; its subscription ends at
zero, at the touch and in `close`, so nothing navigates after the user left.

## ADR-029 Crop and straighten of the page for the PDF, pure Dart, as a step of the background queue (Phase 6.1)

**Decision of the user (after the spike 6.0 and the phone check):** the PDF gets the
page cut out of the photo and straightened; the originals do not change.

- **Method A3 only (pure Dart, package `image`, MIT, already a dependency).** No
  native code, no new package, no APK growth. A1 (OpenCV) was excluded on the
  phone check: wrong cuts, and a deformed page that was already straight (a diagonal
  line in the content). Spike results: `IMAGE_SPIKE_RESULTS.md`.
- **Detection:** brightness and edge candidates on a grey picture of at most 640 px,
  then the **enclosing quad** (the outline that always contains the convex hull of
  the candidate). This is what protects the content: on 77 synthetic scenes it cut
  nothing at confidence 0.5, while `approxPolyDP` cut four pages.
- **One rule, one place:** `PageCropConfig` holds every constant (confidence 0.5,
  detection side 640, area bounds, timeout 8 s, queue depth 2) and
  `trustsDetection(confidence)` is the only place that applies the threshold
  (`>= 0.5`). Each constant has a comment saying what raises or lowers it.
- **The PDF never loses content.** A low confidence, no page found, an exception,
  an out-of-memory, a timeout of 8 s, or a cancel all give the **whole frame** (the
  same working copy as before) for that page, and the scan goes on
  (`PageWholeFrame(reason)`). The scan never fails because of the crop. Only numbers
  go to the log (how many pages were straightened, the whole-frame reasons), never
  content.
- **Originals untouched.** `StoreScanPages`, `./pictures` and the Gallery copy are not
  changed: the crop reads and writes only the cache. Tests compare the originals
  byte for byte before and after.
- **The picture of the PDF** is the straightened working copy, with the same size
  rule (ADR-017: page size = pixels x 72/200) and the same JPEG quality as before.
  **No contrast or shadow processing** (the spike showed no gain; `flat` stays out
  of the app until Phase 6.2, as an option of the user).
- **The OCR reads the cropped picture**, so the text layer of the PDF fits the
  picture of the page. The straightened page replaces the working copy (one working
  file per page).
- **Focal length for the perspective:** read from the EXIF of the original (tag
  0xA405, 35 mm equivalent) into `ImageHeader` and `UprightImage`. If it is missing
  the mean of the opposite sides is used; the limit of accuracy is that a page tilted
  about 20 degrees can come out about 6% narrower. The 35 mm value is turned into
  pixels with `focalPx = f35 * diagonalPx / 43.27`.
- **It runs in its own isolate** (`IsolatePageCropper`), never in the UI isolate. The
  isolate is spawned (not `Isolate.run`) so a timeout or a cancel **kills** it, and
  the target file is deleted only after it has exited, so nothing appears afterwards.

**The queue (`OcrSession`) has two stages** that overlap: *prepare* (upright working
copy, then the crop; one page at a time) and *read* (the OCR; one page at a time).
While page k is read, page k+1 is prepared. At most `prepareAhead = 2` prepared pages
wait for the engine: this is the backpressure that bounds the memory. The reading is
always in capture order, whatever the order the stages end. `add` still returns at
once.

| Case | What happens |
|---|---|
| Undo of the last shot while its page is worked on | The crop is killed, every file of the page is deleted, the result is dropped |
| Cancel / Back after Done (ADR-028) | Every stage stops at once, the crop is killed, no file stays in the cache |
| Discard | `session.dispose` deletes the cache files; `DiscardScan` is as before (ADR-027) |
| "No text" (`skipText`, `stopReading`) | A crop that runs is let to finish; the OCR is skipped; the page goes in the PDF without text |
| Error, timeout or exception in the crop | Whole frame for that page, the scan goes on |

**Cache and clean-up.** The cropped files are in the cache of the app, not in the
user's folder. They are removed at the end, on an error, on a cancel, and at start-up
(`purgeAll`, as in Phase 4).

**Deviation from ADR-018 (named on purpose).** ADR-018 says no picture stays in the
cache after the PDF is stored. In the **preview** mode the preview shows the pages
"as they are in the PDF", so their straightened working copies stay until the result
screen is left (like the captured shots). In **One Click** they are deleted at once,
as before. The preview shows them in a row of thumbnails with a note of how many were
straightened.

**ADR-028:** the stage texts and the cancel behaviour are as before; the stage text
may stay "Processing" with no animation. The only change is that Cancel also kills a
running crop.

**Limits.** 14 of 77 synthetic scenes fall back to the whole frame (small pages and
some combined scenes), and with bad light or a dark background the phone check showed
the same (safe by design). Proposals for Phase 6.2 (not built): detection on a picture
with a mild light flattening used only for the detection, and a lowered area bound for
small receipts. No gain of time is claimed when all pages arrive at once (measured on
the phone: 56.4 s before against 65.4 s with the crop): the gain is in hiding the time
between the shots.


## ADR-030 Flash, tap-to-focus, low light detection and the optional light correction (Phase 6.2)

**Decisions of the user (binding):** a flash button at the top left with Off / Auto / On
(default Off); tap-to-focus; a low light check before and after the shot; in One Click a
dark shot stops the flow with three choices; the shadow removal (`flat`) is **only a choice
of the user**, with a safety valve. The rest below is what was decided to build that.

> **Changed by ADR-031 (Phase 6.2.1):** flash **On** is now the continuous **torch** on the
> preview, not a flash on the shot. Off and Auto are as described here. Everything below
> about "never the torch" is the Phase 6.2 state.

### Flash

- `FlashMode { off, auto, on }` in `domain/lighting/`. The camera port
  (`CameraService`) got `hasFlash`, `flashMode`, `setFlashMode`. The implementation uses
  the `camera` plugin (`FlashMode.off/auto/always`): in CameraX this is the flash mode of
  the **`ImageCapture`** (it fires on the shot), never the torch.
- **Only Off and Auto are remembered.** `FlashMode.storedName` writes On as Auto, and
  `fromStored` reads a missing value as Off and a stored `on` as Auto. So the app can
  **never start with a full flash**; On is always a new choice, and it lives in the cubit
  for the current use (it survives the app going to the background and back, because the
  cubit stays). The store is `FlashPreferenceStore` (port in `domain/ports/`,
  `KeyValueFlashPreferenceStore` over the existing key/value store, key
  `camera.flashMode`), not part of `AppSettings`: it is a camera-screen habit, not a
  setting the user edits.
- **No flash, no button.** The plugin has no call for it, so `SystemHandler.kt` answers
  `hasFlashUnit` from `CameraCharacteristics.FLASH_INFO_AVAILABLE` of the back camera
  (a yes/no crosses the channel).
- The button is under the app bar at the left (the app bar's own top-left place is the
  Back arrow), in Single and Multi, with a state icon and EL/EN accessibility labels.
- **Finding, "flash required" signal:** the `camera` plugin does **not** expose the
  auto-exposure state of CameraX. `ImageCapture` with the Auto flash mode decides inside
  CameraX (the AE pre-capture). The signal could only be had with Camera2 interop
  (`Camera2CameraInfo` / a capture callback) in our own native code bound to the same camera
  session, which the plugin does not allow. So the diagnostics screen shows it as `n/a`, and
  the "low light" decision uses our own brightness metric. Not verified on a phone.

### Tap-to-focus

- A tap on the preview calls `setFocusPoint` and `setExposurePoint` of the plugin (one
  `FocusMeteringAction` for focus and metering at the point) with the point as fractions of
  the preview. The ring is a static circle (no running animation) that disappears by itself
  after 1.5 s. CameraX cancels the action by itself after its own time and the camera goes
  back to continuous focus.
- The size used for the fractions is the size of the preview widget itself (a test caught
  that the first version used the size of the free area around it).
- **Report only, not changed:** the flow of the shot does not wait for the focus. In CameraX
  the `ImageCapture` in its default mode (minimize latency) runs an AF/AE pre-capture only
  when the flash is needed (or the AF mode is not continuous); otherwise it takes the frame
  at once. This is from the CameraX documentation and was **not** measured on a phone. A
  short wait for the focus lock would make sense only if the phone check shows blurred shots
  of close text; it was not added.

### The metric of the light

- From the **Y (luma) level** of a reduced picture: the **paper level** (95th percentile)
  and the **contrast** (95th minus 5th percentile), both 0 to 100. The mean alone misleads
  (it depends on how much text there is; a unit test shows the paper level does not).
- **Decision:** a picture is "dark" when the paper level is **below
  `LightingConfig.minPaperLevel` = 40** (the middle of the 30 to 50 range of the user). It is
  the only place the threshold is applied (`LightingConfig.isLowLight`), and every constant
  of the detection is in that one file with a comment on what raises or lowers it. The
  contrast is **not** a reason to warn: more light does not give faded ink back (thermal
  paper); it is shown on the diagnostics screen.
- **Synthetic evaluation** (`tool/light_metric_eval.dart`, table in
  `IMAGE_SPIKE_RESULTS.md`): a page on a table or on a dark background gives paper = light
  level x 0.99, so 40 separates "40% of the light" from "50%". This is a **linear**
  model: a real phone raises the exposure in the dark, so the real numbers must come from
  the diagnostics screen (`PHASE_6_2_VALIDATION.md`), and the threshold is a starting value.
  A faint thermal receipt lowers the paper level too (72 at full light in the synthetic
  scene), so such a receipt in dim light can be called dark earlier: part of the phone check.
- **Before the shot:** the plugin gives **every** frame of the analyser to Dart (about 30 a
  second, 460 KB each) and has no rate option. So the analyser is switched on only to
  receive **one** frame and off again for 400 ms (`startImageStream` / `stopImageStream`):
  about 2.5 samples a second, with nothing copied in between. The metric is computed in a
  background isolate on a transferred buffer (every 6th pixel of the Y plane), never in
  the UI isolate. The analysis stops during a shot and when the camera closes. The mark
  "Low light" next to the flash button changes only after **two samples in a row agree**
  (`LowLightDebouncer`). The cost on the preview was measured on the emulator, see
  `PHASE_6_2_VALIDATION.md`.
- **After the shot:** `FileLightMeter` makes a 160 px copy with the native decoder
  (`inSampleSize`, the 12 MP picture is never decoded), takes the metric in an isolate and
  deletes the copy at once (ADR-018).

### The flow of the warning

| Case | What happens |
|---|---|
| One Click, **Single** | Measured **before** `save()`. A dark shot stops the flow with a dialog: **New shot** (the shot was never stored, so only the cache is cleaned, like the undo of a page: nothing in `./pictures`, nothing in the Gallery), **Continue anyway**, **Continue with light correction** (the page is marked for the correction in the queue, then the scan goes on) |
| One Click, **Multi** | The shot is measured **behind** the camera screen (the rhythm is not slowed). A dark page is only marked; a non-blocking bar says "Dark shot: retake?" with "New shot" (= the undo of that page) and a close button. The capture button stays active. At "Done" the **summary** appears when a page is flagged and has no decision (back to the camera / continue anyway / continue with correction): a dark page is **never sent silently** |
| **Preview** | No interruption. The flagged pages go to the result screen: a banner with **Correct the light** and **Keep as is** |

The original is stored at "Done" (Multi) or right after the decision (Single), so there
is nothing to delete when the user retakes a shot. The decision logic is pure
(`LowLightPolicy`) and tested without a screen.

### The light correction (`flat`)

- **Only an action of the user.** There is no switch that applies it to every scan. The
  code of the spike was moved to `services/imaging/flatten_light.dart` (pure Dart,
  unchanged method), run by `IsolateLightEnhancer` in its own isolate that is killed on
  a cancel or a timeout (20 s), like the crop (ADR-029).
- **Safety valve (`OcrSession.requestEnhance`):** the corrected picture is read too, and the
  version with **more words** is the page (a tie keeps the original). The picture of the PDF
  and its text layer come from the **same** version, the rejected picture is deleted, and
  the PDF never loses content. The cost of the second reading applies only to a page the
  user asked about. A page that is already read is read again **only in its corrected
  version**.
- **Preview banner:** after the correction the PDF is made again; the old PDF is deleted
  **first, by its URI**, so the new one has the same name (the other order would leave
  `-2`). If the new PDF fails, the usual "try again" of the PDF is there and the pictures are
  untouched. The originals are never read or changed by any of this (tests compare them byte
  for byte).
- Words are only counted, never kept or logged; the log has numbers only.

### The diagnostics screen

Hidden: five taps on the app name at the end of Settings (3 s window). It opens its own
camera, shows the live paper level and contrast, the threshold, "would warn" yes/no, a test
shot (measured and deleted at once) with the same numbers, the flash button (not remembered)
for with/without flash, and the `flash required` signal as `n/a`. It stores no picture and no
text.

### Limits

- The real flash, the real light of a room and the focus of a real lens cannot be tested on the
  emulator; they are in `PHASE_6_2_VALIDATION.md` for the phone.
- The threshold is a starting value to be set from the numbers of the phone.
- A shot that cannot be measured is never called dark (a missing meter or a decode error
  gives no warning), so the feature can only add a question, never block a scan.
- Not built (item E of the request): detection with a mild light flattening only for the
  detection of the page. No measurement was made, so no claim.

## ADR-031 Torch for flash On, the light mark with the torch, a second light threshold (Phase 6.2.1)

**Why.** The phone check of Phase 6.2 found that with flash On in a dark room the live
measurement gave 11 and the mark warned, while the shot (with the flash) gave 86 and read
fine. The flash only fired on the shutter, so focus, exposure and the preview were still
dark. The user asked for a torch while On, a mark that sees the lit scene, and the
analysis of a second light threshold (below about 40 the correction does not help).

### Feasibility (checked first)

The `camera` plugin used here (`camera` 0.12.1, `camera_android_camerax` 0.7.5+1) supports
`FlashMode.torch` on the **same camera session**: `setFlashMode(torch)` calls CameraX
`CameraControl.enableTorch(true)` and, for the shot, sets the `ImageCapture` flash mode to
**off** (`takePicture` does this when the torch is on), so there is **no double flash**.
Leaving the torch mode calls `enableTorch(false)`. No native code of our own was needed (the
`hasFlashUnit` method of `SystemHandler.kt` stays as it was). **Not verified (the emulator
has no flash unit, `hasFlash` is false there):** that the LED really lights, that it
survives the analyser's start and stop of the image stream (a rebind of the use cases),
that the exposure settles in the time below, and that a shot with the torch has no second
flash. All of it is in `PHASE_6_2_1_VALIDATION.md` for the phone. The plugin does not
report the real state of the LED: `torchLit` is what the app asked for and the plugin
accepted.

### Behaviour

- **Off and Auto: unchanged** (the system fires the flash on the shot; Auto only when needed).
- **On = torch on the preview.** The port `CameraService` got `torchLit` and
  `setTorchLit(bool)`. `setFlashMode(on)` only sets the mode (the capture mode is Off, the
  torch does the work) and **never lights the torch by itself**; the cubit lights it with
  `setTorchLit(true)` when the camera is on screen. So the screen can put the torch out and
  light it again **without changing the choice**.
- Still **stored as Auto** on restart (ADR-030), so the app never opens with the torch lit.

### The torch is lit only while the camera is on screen

`ScanCubit._torchWanted` is the single rule: the choice is On, the phone has a flash, the
phase is `ready` or `capturing`, no dark-shot dialog and no failed-shot message covers the
camera, and the app is not `inactive`. `onChange` re-evaluates it on every change of phase,
prompt or error, through a **serial queue** (so quick changes cannot cross), never inside
the emit. It covers: Back / dispose / `cancel` (and `PluginCameraService.close` puts the
torch out **before** disposing, so it does not depend on the unbind), background (`paused`),
lock screen and system dialogs (`inactive` / `hidden`: only the torch goes out, the camera
stays open), saving after "Done" or after the Single shot, Discard (the camera is already
closed there), a failed shot, a camera that is opened again (`open()` starts with the torch
out; the light comes back after the screen shows the camera), and a change of the flash to
Off or Auto. Returning (foreground, a new page of Multi, a new shot after a dark-shot
dialog, a retry after a failed shot) lights it again while the choice is still On.

### Idle timeout

`LightingConfig.torchIdleTimeout` = 120 s without a shot or tap-to-focus: the torch goes out,
the choice becomes **Auto** (and is stored as Auto), and the screen shows once a short
message that it was switched off so the phone does not get warm. The timer restarts on every
shot and every tap-to-focus. The value is injectable into `ScanCubit` (tests use a few
milliseconds; no test waits for 120 s).

### The "low light" mark with the torch

When the real torch state changes, the cubit drops the samples for
`LightingConfig.torchSettleDelay` (500 ms) and calls `LowLightDebouncer.restart()`, which
forgets the last sample **but keeps the mark**. The mark therefore neither shows nor hides
on an old or half-adjusted sample; it changes only after two fresh samples agree (the flicker
guard of ADR-030). A shot that follows a lighting waits for the same settle time. The
decision rule (`minPaperLevel`) and the check on the shot (One Click, before the save) are
**not changed**.

### Two light thresholds (structure only)

`minPaperLevel = 40` stays: it decides **whether** to warn. A second constant,
`enhancementHelpsMinPaperLevel = 40`, decides the **words**: below it the dialog (Single),
the summary (Multi) and the banner (preview) say honestly that the page is very dark and the
light correction will most likely not fix the result, and **"New shot"** is the primary
choice (in the banner a new first button, which asks the usual discard question, because a
retake of a stored scan is a discard). The other choices stay. Above it and below
`minPaperLevel` the Phase 6.2 text stays. The state carries the flag as `darkNeedsRetake`
(any flagged page below the second threshold), through `ScanResultArgs` to the banner.

**Consequence of today's values.** The two values are both 40, so the zone "dark but
correctable" is **empty now**: every shot that warns also gets the "very dark, retake first"
words. This is deliberate and honest for the phone check (a PDF from a shot below about 40
stayed unreadable), but it is a visible change of the text. The real values wait for the
dusk calibration (`PHASE_6_2_1_VALIDATION.md`); the proposal of the user is a warning
threshold of about 70 and a second one of 40. Both are injectable in the tests, which cover
the zone between them.

### Diagnostics screen

Three new lines: the torch (lit / out), the time since it was last lit (updated every second),
and whether the latest live sample was taken after the torch was lit **and settled**. The
screen also puts the torch out when it loses focus and when it is left. Its flash button's On
is now the torch.

### Clean `flutter analyze`

`spikes/**` is excluded in `analysis_options.yaml`: the spikes are separate Flutter projects
with their own dependencies, and in a fresh clone they gave 439 errors unrelated to the app.
The plain `flutter analyze` is the command again.

### Limits

- The real LED, the settling of the real exposure and the heat after two minutes are only on
  the phone. The emulator test (`integration_test/torch_camera_test.dart`) shows that the
  switch does not break the camera, the analyser or the shot, and that **without a flash unit
  no torch call is made**.
- The torch of a shot taken while the analyser runs: whether the analyser's rebinds switch the
  torch off is the first thing to check on the phone. If they do, the fix is to light it again
  after each rebind (not built, so as not to flicker the light on a guess).

## ADR-032 Dynamic page limit for Multi Page, one guide text for the wizard and Help, the busy capture button (Phase 6.3, Polish)

**Why.** A Multi Page scan could grow until the final PDF no longer fitted in a message the
provider takes; the user only learned it at the end (`MailTooLarge`). The user also asked for
a guide in the wizard and in Settings, a first-open hint for Multi Page, and a look at the
capture button that stays inactive for about half a second after a shot.

### The page limit

- **Hard maximum 25 pages** (`PageBudgetConfig.hardMaxPages`, one place).
- **Size limit = the limit of the provider**, from the one source that already exists:
  `MailSizePolicy.maxAttachmentBytes(provider)` (about 18.2 MB for Gmail, about 14.6 MB for
  Outlook and Yahoo). No second table of numbers. The same limit holds for the share route
  (same provider). With no provider chosen, the strictest limit is used.
- **XX = min(25, floor((limit * margin - fixed) / average page))**, margin 0.9
  (`PageBudgetConfig.margin`). It is computed again after **every** page and can go up or down.
  At least one page is always allowed (a page bigger than the whole limit leaves XX = 1 and the
  final check says no).
- **What is known between the shots (found in the code, not assumed).** The PDF is built at the
  end, but the `OcrSession` prepares every page in the background right after its shot: the
  upright working copy and the crop (Phase 6.1). **That JPEG goes into the PDF as it is**
  (`pdf_writer.dart`: "a JPEG goes in without new compression"). So the size of that file is
  the size the page has in the PDF, and it is known before the reading (OCR) of the page.
  `OcrWorkStore.sizeOf` reads it and `OcrPageState.imageBytes` carries it; `ScanCubit` listens
  to the session and keeps `pageBytes` in the state. A page that is not prepared yet (quick
  shots) counts as the average of the others; before any page is known a fallback of 1.5 MB
  is used. The size of the original shot is **not** used (it is a different file, much bigger).
- **Estimator in `domain/scan/`** (`PageBudgetEstimator`, `PageBudgetConfig`): pure Dart, the
  limit and the numbers are injected. The overheads are measured, not guessed
  (`test/services/pdf/page_budget_accuracy_test.dart`): about 3.5 KB once and about 1 KB per
  page of 120 words; the defaults are 24 KB and 3 KB (on purpose above the measurement: Greek
  text and dense pages use more).
- **Display.** Before page 5: "Pages: 3" as before. From page 5, or earlier when the pages
  already use more than half of the limit: "Pages: 5/18". With 2 or fewer pages left: a short
  message that about N pages still fit (approximate). At XX: the shot is blocked (the button
  dims) with a message that explains it and suggests "Done" and a new document for the rest.
  If the estimate falls below the pages already taken, **no page is removed**: the limit is
  simply reached. "Done" always stays possible. One Click Multi and Multi with preview are
  the same cubit, so both behave the same.
- **The final check stays.** `SendScanPdf` still refuses a PDF over the limit (`MailTooLarge`);
  the budget is only a way to avoid getting there.

### How good is the estimate (measured, synthetic pages)

- **Sum error** (measured pictures plus overheads against the real PDF written by the real
  writer): mean 1.0 %, max 1.5 % (the defaults overestimate a little, on purpose).
- **Projection error** (what the budget expects for the whole scan from the first k pages,
  against the real PDF): mean 11 %, max 47 % when the pages are very different (a blank page,
  a text page and a photo page in one scan). This is **larger than the 10 % margin**, as the
  request asked to check. It does not decide the outcome, because the budget is computed again
  after every page and the stop is decided on the **real sum so far**.
- **What decides the outcome** was simulated: scans taken up to the limit of the budget, 2000
  per case, three kinds of scans (same kind of page; a mix of text, photo and blank pages;
  small pages first and photos later). **With margin 0.9 no scan went over the limit; the worst
  one used 99 % of it** (mix). With 0.95 about 5 % of the mixed scans went over. The mean
  fill is 88 % at 0.9. The page sizes of the simulation are assumed, so the number waits for
  the phone check (`PHASE_6_3_VALIDATION.md`). **Proposal:** keep 0.9 for now; if the phone
  check shows a scan above 97 % of the limit, lower it to 0.85 (worst 94 %, mean fill 83 %).

### One text for the wizard and Help

- `AppStrings.guideSections` is the only place with the guide text, per language: sections with
  a title, short `lines`, longer `details`, and a flag `inWizard`. The last page of the wizard
  shows the short lines of the `inWizard` sections; Help shows all sections with their details;
  the first-open hint of Multi Page takes its lines from the `multi` and `cancel` sections. They
  cannot differ. The numbers in the texts (25 pages, 2 minutes, 18 and 14 MB) come from the
  constants and the provider limits, not from copies.
- **Help only:** the e-mail steps (the existing texts of the app-password guide are reused) and
  **"What the app does not cover"**. The last page of the wizard does not have them.
- **The wizard has a sixth step** after the last setting, the guide page. It asks nothing.
  **Everything, including `firstRunCompleted`, is saved at the last setting**, as before, so
  the guide page never blocks a working app. "Finish" on the guide page only goes home. An
  install that finished the wizard earlier sees the guide through Help, "See the guide again",
  which is a plain page without any question.
- **First-open hint of Multi Page:** `MultiPageHintStore` (a flag in the key/value store, nothing
  of the user). Shown once, when Multi is chosen for the first time; the flag is written when it
  is shown, so a killed app does not repeat it.

### The capture button (measured on the emulator)

The button is inactive while `PluginCameraService.capture` runs. Measured with 12 quick shots
while the light analyser runs: **waiting for the analyser 535 ms on average (max 807), taking
the picture 509 ms, moving the file about 40 ms, total about 1.08 s.** The wait for the analyser
was **our** delay: `_stopAnalysis` waited for the loop to wake from its sleep of 400 ms. It now
wakes at once when a stop is asked (the image stream is still stopped before `takePicture`, as
before, so the order and the safety of the stages are the same): **22 ms on average, total about
0.6 s.** What is left is the camera itself (`takePicture`), which is native and not ours to
shorten, so the button now shows that it is busy (dimmed, a small spinner, the label "Taking
photo..."). The phone numbers are different and wait for the check.

### The rate of the analyser samples (only a finding)

About 1.3 samples a second on the emulator against the 2.5 of the design. The 2.5 was
1 / 400 ms, which leaves out the cycle itself (open the image stream, wait for one frame, close
it, measure): about 380 to 415 ms, so one sample every 780 to 820 ms. Not a defect, and
nothing was changed. Whether the phone is faster is for the phone check.

### Not done

- No new package. No change to the order or the safety of the stages of the queue (cancel,
  Discard, the torch).
- The real values of the margin and of the fallback page size wait for real shots.
