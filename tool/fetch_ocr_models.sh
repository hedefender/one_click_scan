#!/usr/bin/env bash
# Downloads the OCR models listed in assets/ocr/manifest.json into
# assets/ocr/models/ and verifies the SHA-256 of every file. The models are not
# in git (about 28 MB). Run once from anywhere; fails loudly on a mismatch.
set -eu
cd "$(dirname "$0")/.."
dart run tool/ocr_models.dart fetch
