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
