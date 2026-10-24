#!/usr/bin/env bash
# Puts the models and the test font where the spike bundles them.
# Models: the ones of the main app (run ../../tool/fetch_ocr_models.sh first).
# Font: Noto Sans Regular (SIL Open Font License 1.1), used only to measure the
# size of an embedded font and to compare with the glyphless approach.
set -eu
cd "$(dirname "$0")/.."
mkdir -p assets/models assets/fonts
for f in det_mobile.onnx rec_greek.onnx dict_greek.txt rec_latin.onnx dict_latin.txt; do
  cp "../../assets/ocr/models/$f" "assets/models/$f"
done
curl -sL -o assets/fonts/NotoSans-Regular.ttf \
  https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Regular.ttf
echo done
