#!/bin/bash
# Downloads the models, traineddata and fonts the OCR spike bundles as assets.
# Run once from spikes/ocr_spike. Build-time only: the app itself never uses the network.
set -e
cd "$(dirname "$0")/.."
mkdir -p assets/models assets/tessdata_fast assets/tessdata_best assets/fonts

# PP-OCRv5 recognition (Apache-2.0), ONNX conversion by monkt/paddleocr-onnx
H=https://huggingface.co/monkt/paddleocr-onnx/resolve/main/languages
for l in greek latin eslav; do
  curl -sL -o assets/models/rec_$l.onnx $H/$l/rec.onnx
  curl -sL -o assets/models/dict_$l.txt $H/$l/dict.txt
done
# PP-OCRv5 mobile detection (Apache-2.0), 4.8 MB, ONNX conversion by ilaylow/PP_OCRv5_mobile_onnx
curl -sL -o assets/models/det_mobile.onnx https://huggingface.co/ilaylow/PP_OCRv5_mobile_onnx/resolve/main/ppocrv5_det.onnx

# Tesseract traineddata (Apache-2.0)
for l in ell eng spa rus; do
  curl -sL -o assets/tessdata_fast/$l.traineddata https://github.com/tesseract-ocr/tessdata_fast/raw/main/$l.traineddata
  curl -sL -o assets/tessdata_best/$l.traineddata https://github.com/tesseract-ocr/tessdata_best/raw/main/$l.traineddata
done

# Noto Sans / Noto Sans Mono (SIL OFL 1.1), used only to draw the synthetic documents
N=https://github.com/notofonts/notofonts.github.io/raw/main/fonts
curl -sL -o assets/fonts/NotoSans-Regular.ttf $N/NotoSans/hinted/ttf/NotoSans-Regular.ttf
curl -sL -o assets/fonts/NotoSans-Bold.ttf $N/NotoSans/hinted/ttf/NotoSans-Bold.ttf
curl -sL -o assets/fonts/NotoSansMono-Regular.ttf $N/NotoSansMono/hinted/ttf/NotoSansMono-Regular.ttf
echo done
