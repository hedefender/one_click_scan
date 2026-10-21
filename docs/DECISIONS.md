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
`YYYY-MM-DD_HH-MM-SS` (the same text as the e-mail subject). PDF:
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

