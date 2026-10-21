# Data contract: JSON schema v1

Reference copy of the contract agreed with the Budget app. It replaces the
formats in the original description (`version/created/ocr_text/...`) and in the
original roadmap (`formatVersion/scanId/...`). Implemented in Phase 6.

## Rules

- One `.json` file per scan. UTF-8 without BOM. camelCase.
- Written only for **Receipt** scans, and only when OCR text is non-empty.
  Document scans (`genericDocument`) produce PDF only and no JSON.
- Receipt subtypes: `receipt`, `utilityBill`, `invoice`. Absence of
  `documentType` means unknown.
- The Scan app never modifies OCR text (for example the Latin µ U+00B5 versus
  Greek μ U+03BC). Normalization is Budget's job.

## Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `schemaVersion` | integer | yes | Currently `1` |
| `documentId` | string, 1–128 chars after trim | yes | UUID v4 recommended, unique per scan. Budget de-duplicates on it (first import wins) |
| `createdAt` | ISO 8601 | yes in practice | With offset (e.g. `2026-09-19T12:56:44+03:00`) is an exact instant. Without offset it is read as device time. Prefer with offset |
| `ocrText` | string | yes | Non-empty after trim |
| `pdfPath` | string | no | **File name only**, no directory |
| `imagePaths` | string[] | no | **File names only** |
| `language` | string | no | BCP-47, e.g. `el`, `en` |
| `documentType` | string | no | `receipt`, `utilityBill`, `invoice` |

Unknown fields are ignored by Budget, so new optional fields do not break
anything. Changing or removing a field requires a new major `schemaVersion`.

Optional additions that Budget will simply ignore (for example OCR confidence
or the scan mode) may be added later without a version bump.

## Budget limits

5 MiB per file, 50 files per import.

## Files and names

Budget refers to PDFs and images by name only, so all files of one scan live
in the same user-chosen folder. Planned naming (flat, prefixed by the id):
`<documentId>.json`, `<documentId>.pdf`, `<documentId>_1.jpg`, ...
Budget will also be able to import a PDF on its own, without JSON.
