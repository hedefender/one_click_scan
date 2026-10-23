# OCR language packs: what exists and what is confirmed (Phase 1.6b)

Research only; no app code. Everything in the "Source" column was opened on
2026-10-23. Anything not opened is in section 7 and must not be promised to
users. Scan uses PaddleOCR PP-OCRv5 through ONNX Runtime (see
`OCR_SPIKE_RESULTS.md`); a "language pack" here means one recognition model plus
its character dictionary (the detection model is separate, section 4).

## 1. Sources opened

| Id | Source |
|---|---|
| S1 | PaddleOCR docs, PP-OCRv5 multilingual: https://www.paddleocr.ai/latest/en/version3.x/algorithm/PP-OCRv5/PP-OCRv5_multi_languages.html |
| S2 | PaddleOCR repository licence: https://github.com/PaddlePaddle/PaddleOCR/blob/main/LICENSE (Apache-2.0) |
| S3 | Official model cards and file lists (Hugging Face API, `?blobs=true`): `PaddlePaddle/latin_PP-OCRv5_mobile_rec`, `eslav_PP-OCRv5_mobile_rec`, `el_PP-OCRv5_mobile_rec`, `PP-OCRv5_mobile_rec`, `PP-OCRv5_mobile_det`, `PP-OCRv5_server_det` |
| S4 | ONNX mirror `monkt/paddleocr-onnx` (README and API): https://huggingface.co/monkt/paddleocr-onnx, repo sha `7b02d0a30a07ba2b92ad1ff5a8941ae2c633de65`, last modified 2025-10-07, licence apache-2.0 |
| S5 | ONNX mirror `ilaylow/PP_OCRv5_mobile_onnx` (card and API): https://huggingface.co/ilaylow/PP_OCRv5_mobile_onnx, repo sha `f97b337b3ac256f9dffcac5fc53955082d919d58`, last modified 2026-03-19, licence apache-2.0 |
| L | Local checks on the files the spike already uses (SHA-256, dictionary contents) |

## 2. Recognition models (PP-OCRv5 mobile, official names)

Accuracy is the vendor figure on a per-language dataset (S1); the datasets
differ, so the numbers are **not comparable between rows**, and a line counts as
wrong if any character is wrong.

| Official model (S1) | Languages stated by S1 section 5 | Accuracy (S1) | ONNX in the mirror S4 | rec.onnx size (S4) | Dictionary |
|---|---|---|---|---|---|
| `el_PP-OCRv5_mobile_rec` | Greek, English | 89.28 | `languages/greek/` | 7,791,200 B | `dict.txt`, 354 lines (L) |
| `latin_PP-OCRv5_mobile_rec` | 47 Latin-script languages (list below); **English is not in the list** | 84.7 | `languages/latin/` | 7,862,832 B | 502 lines (L) |
| `eslav_PP-OCRv5_mobile_rec` | Russian, Belarusian, Ukrainian, English | 81.6 | `languages/eslav/` | 7,870,092 B | 517 lines (L) |
| `en_PP-OCRv5_mobile_rec` | English | 85.25 | `languages/english/` | 7,830,888 B | 1,416 B file |
| `cyrillic_PP-OCRv5_mobile_rec` | Russian, Belarusian, Ukrainian, Serbian (Cyrillic), Bulgarian, Mongolian, Kazakh, Kyrgyz, Tajik, Macedonian, Tatar and about 20 more, English | 80.27 | **none** (not in S4) | n/a | n/a |
| `korean_PP-OCRv5_mobile_rec` | Korean, English | 88.0 | `languages/korean/` | 13,401,252 B | 47 KB file |
| `th_PP-OCRv5_mobile_rec` | Thai, English | 82.68 | `languages/thai/` | 7,873,480 B | 1,767 B file |
| `arabic_`, `devanagari_`, `ta_`, `te_PP-OCRv5_mobile_rec` | Arabic script (Arabic, Persian, Urdu, ...), Hindi/Marathi/Nepali/Sanskrit..., Tamil, Telugu, each with English | 81.27 / 84.96 / 94.2 / 87.65 | S4 has `arabic`, `hindi`, `tamil`, `telugu` but they are **PP-OCRv3** ("legacy"), not v5 | about 9.0 MB | n/a |
| `PP-OCRv5_mobile_rec` (default) | Simplified/Traditional Chinese, English, Japanese, pinyin | 80.15 average (S3) | `languages/chinese/` | 84,468,836 B in S4 (the mirror's file is not the 16.5 MB mobile model; not investigated) | 74 KB file |

Latin-script languages of `latin_PP-OCRv5_mobile_rec` (S1, names as listed):
French, German, Afrikaans, Italian, Spanish, Bosnian, Portuguese, Czech, Welsh,
Danish, Estonian, Irish, Croatian, Uzbek, Hungarian, Serbian (Latin),
Indonesian, Occitan, Icelandic, Lithuanian, Maori, Malay, Dutch, Norwegian,
Polish, Slovak, Slovenian, Albanian, Swedish, Swahili, Tagalog, Turkish, Latin,
Azerbaijani, Kurdish, Latvian, Maltese, Pali, Romanian, Vietnamese, Finnish,
Basque, Galician, Luxembourgish, Romansh, Catalan, Quechua. S4 summarises the
pack as "French, German, Spanish, Italian, Portuguese, + 27 more".

Model-card quirks (S3): the `latin` card's intro sentence says "Korean" (a
copy-paste error; its table is for Latin-script data); the `el` card metadata
lists only `en`. Licence on all six cards: apache-2.0.

## 3. Answers to the questions

**One pack for many languages?** Yes for the Latin script: one `latin` model
(7.9 MB) covers de, fr, it, es, pt, nl, pl, tr, ... (S1). Cyrillic: `eslav`
covers ru, uk, be (+ en); the wider `cyrillic` model (Bulgarian, Serbian,
Kazakh, ...) exists officially but has no ONNX in the mirror we use. Greek has
its own pack. So the packs the user would download are about 8 MB each:
`greek`, `latin`, `eslav` (+ optional extras).

**Do they read English too?**
- Greek and East Slavic: S1 lists English for both. Locally (L) both
  dictionaries contain all of A-Z, a-z and 0-9 (and the euro sign).
- Latin: S1 does **not** list English among the languages, but the dictionary
  (L) has all of A-Z, a-z, 0-9, the euro sign and 129 accented Latin letters,
  so English words are inside its character set.
- **How well** is not confirmed. The spike's synthetic documents (Phase 1.5)
  are in one language each (el, es, ru, with numbers, dates and codes) and
  scored CER 1.8% overall; mixed-language pages were not measured. Do not claim
  "el+en" quality until a mixed test set exists.

**Is the 4.8 MB detection model the same for all languages?** The sources do
not state that the detector is language-specific: the official detection cards
(S3) list Chinese, English and Japanese benchmarks only, S1 does not name a
detector, and S4 says only "use v5 detection with v5 recognition models" for
all v5 languages. What is confirmed (L and Phase 1.5): the spike uses the same
`ppocrv5_det.onnx` (4,826,518 B, mirror S5, the card says it is converted from
the official `PP-OCRv5_mobile_det`) in front of the Greek, Latin and East Slavic
recognisers, with 10 synthetic documents in three languages at 156/160 key
tokens. Treat as "works for el/es/ru on our test set", not as a vendor
guarantee. Note: S4's own `detection/v5/det.onnx` is **88 MB** (matches the
size class of the official *server* detector, 87.9 MB in S3, but S4 does not say
which it is), so the two mirrors do not offer the same detector.

**Official ONNX?** None. The official repositories (S3) contain only
`inference.pdiparams`, `inference.json`, `inference.yml`, `config.json`: Paddle
format. ONNX files exist only as third-party conversions (S4, S5, both with
paddle2onnx; S4: opset 11, FP32).

**Licence.** Code: Apache-2.0 (S2). All six official model cards: apache-2.0
(S3). Both mirrors: apache-2.0 (S4, S5). S1 itself does not state a licence
for the weights beyond the repository; the cards do.

## 4. Pack candidates for Scan (what is confirmed, what is not)

| Scan pack | Model | Confirmed | Not confirmed |
|---|---|---|---|
| el+en | greek rec 7.8 MB + dict | official name and 89.28 on Greek data; used in the spike | English quality on mixed pages |
| de/fr/it/es/pt (+en) | latin rec 7.9 MB + dict | official language list (47); spike scored es synthetic docs | per-language accuracy for de, fr, it, pt (only es was tested); English quality; ß/accents on real scans |
| ru (+en, uk, be) | eslav rec 7.9 MB + dict | official language list; spike scored ru synthetic docs | English quality; Bulgarian/Serbian need `cyrillic` (no ONNX mirror) |
| bg, sr, kk, ... | `cyrillic` | official model exists (80.27) | no ONNX; would need our own paddle2onnx conversion |
| Arabic, Hindi, ... | v3 only in mirror | official v5 models exist | v5 ONNX not available; v3 quality unknown here |
| zh, ja, ko, th | chinese/korean/thai in S4 | files exist | out of scope for now; the `chinese` file is 84 MB |

Each user download would be: one recognition model (about 8 MB) + dictionary
(under 2 KB); the shared detector (4.8 MB) ships once. The optional ArgMax
variant of Phase 1.6 (`tool/make_rec_variants.py`) adds about 100 bytes.

## 5. URL stability and hosting

Checksums (SHA-256 = Hugging Face LFS id from S4/S5; the three recognisers and
the detector were **also computed locally from the files the spike downloaded
and match exactly** (L)):

| File | SHA-256 |
|---|---|
| `monkt/paddleocr-onnx/languages/greek/rec.onnx` | `13373f736dbb229e96945fc41c2573403d91503b0775c7b7294839e0c5f3a7a3` |
| `.../languages/latin/rec.onnx` | `614ffc2d6d3902d360fad7f1b0dd455ee45e877069d14c4e51a99dc4ef144409` |
| `.../languages/eslav/rec.onnx` | `dc6bf0e855247decce214ba6dae5bc135fa0ad725a5918a7fcfb59fad6c9cdee` |
| `ilaylow/PP_OCRv5_mobile_onnx/ppocrv5_det.onnx` | `1eb7b4f7ab657ebd1c66d5f79bca7497f29768a2e3c15e52daecbba1a8e4a039` |

Observations (confirmed from S4/S5): both repos are small third-party
accounts (66 and 1 likes), not gated; S4 was created and last modified on 2025-10-07
and S5 was last modified 2026-03-19. Official PaddlePaddle URLs exist for the
Paddle-format files but not for ONNX.

Options for our own hosting (this section is reasoning, not verified against
the providers' current terms in this session; check before deciding):
1. **Pin by commit.** Download URLs of the form `.../resolve/<repo sha>/...`
   point at a fixed revision, but a third-party repo can still be deleted or
   made private; do not make the app depend on it at runtime.
2. **Our own copy** (GitHub Releases of this project or another static host),
   with the SHA-256 above verified by the app after each download, so a
   mirror change cannot silently alter results. The Apache-2.0 licence permits
   redistribution with the licence text and notice; the mirrors' README
   states commercial use is allowed.
3. **Convert ourselves** from the official Paddle files with paddle2onnx
   (S3 files, S4 states which tool and opset they used). This removes the
   third-party link in the chain and is the only route to `cyrillic` and v5
   Arabic/Indic packs. It needs a Python toolchain and a re-run of the accuracy
   guard (CER/key tokens).

## 6. Recommendation for the pack catalogue (for the user to decide)

Start with the three packs the spike has measured: **greek**, **latin** (es
measured; de/fr/it/pt are covered by the vendor's list but untested) and
**eslav** (ru measured), all hosted by us with pinned SHA-256, plus the shared
detector. Add other packs only after a conversion and a measurement.

## 7. Not confirmed (do not promise)

- Any language other than el, es, ru has **no measurement of ours**.
- English quality of any model on mixed-language pages.
- Which official detector (mobile or server) is in `monkt/.../detection/v5/det.onnx`,
  and why the `chinese/rec.onnx` there is 84 MB.
- Whether paddle2onnx conversion of `cyrillic`, `devanagari`, `ta`, `te` works
  without changes.
- Character counts of the official dictionaries (the cards do not state them);
  the line counts above are of the mirror's `dict.txt` for the three packs the
  spike downloaded.
- Current hosting terms of Hugging Face and GitHub Releases (section 5 is
  reasoning).
- The app's download size claims per pack: only the sizes above (file sizes
  from the API) are verified, not compressed transfer sizes.
