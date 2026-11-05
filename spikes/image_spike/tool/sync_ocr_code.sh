#!/usr/bin/env bash
# Copies the OCR engine of the main app into this spike (option (a): a copy,
# the main app is not touched). Run from spikes/image_spike:
#
#   tool/sync_ocr_code.sh
#
# Code goes to lib/ocr_copy/ with the same relative layout, so the relative
# imports keep working. The models (about 20 MB, not in git in either project)
# are copied to assets/ocr/models/ and the manifest to assets/ocr/. The commit
# of the main app the copy was taken from is written to lib/ocr_copy/SOURCE.txt.
set -eu
APP="../.."
DEST="lib/ocr_copy"
rm -rf "$DEST"
mkdir -p "$DEST/core/logging" "$DEST/domain/entities" "$DEST/domain/ocr" \
  "$DEST/domain/ports" "$DEST/services/ocr/paddle" assets/ocr/models
cp "$APP/lib/core/logging/app_logger.dart" "$DEST/core/logging/"
for f in ocr_line ocr_outcome ocr_progress ocr_result upright_image; do
  cp "$APP/lib/domain/entities/$f.dart" "$DEST/domain/entities/"
done
cp "$APP"/lib/domain/ocr/*.dart "$DEST/domain/ocr/"
cp "$APP/lib/domain/ports/ocr_engine.dart" "$DEST/domain/ports/"
cp "$APP"/lib/services/ocr/paddle/*.dart "$DEST/services/ocr/paddle/"
for f in paddle_ocr_engine paddle_worker ocr_model_store model_verification; do
  cp "$APP/lib/services/ocr/$f.dart" "$DEST/services/ocr/"
done
cp "$APP/assets/ocr/manifest.json" assets/ocr/
cp "$APP"/assets/ocr/models/*.onnx "$APP"/assets/ocr/models/*.txt assets/ocr/models/
{
  echo "Copied from the main app on $(date +%F)."
  echo "Main app commit: $(git -C "$APP" rev-parse HEAD)"
  echo "Uncommitted changes under lib/ocr or assets/ocr in the main app at that time:"
  git -C "$APP" status --short -- lib/services/ocr lib/domain/ocr lib/domain/entities assets/ocr | sed 's/^/  /'
} > "$DEST/SOURCE.txt"
echo "copied; see $DEST/SOURCE.txt"
