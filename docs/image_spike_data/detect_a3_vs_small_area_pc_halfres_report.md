### A3 pure Dart: 77 images (73 with a page, 4 without)

Raw detection (best candidate, no threshold), pages only: IoU >= 0.9 in 90.4%, nothing cut in 97.3%, median IoU 0.978, median corner error 0.40% of the diagonal (pages fully in the frame).

| threshold | used | good | loose | **cuts content** | false positive (no page) | fallback (whole frame) |
|---|---|---|---|---|---|---|
| 0.0 | 77 | 66 | 5 | **2** | 4 | 0 (0.0%) |
| 0.1 | 66 | 65 | 1 | **0** | 0 | 11 (14.3%) |
| 0.2 | 64 | 63 | 1 | **0** | 0 | 13 (16.9%) |
| 0.3 | 63 | 62 | 1 | **0** | 0 | 14 (18.2%) |
| 0.4 | 63 | 62 | 1 | **0** | 0 | 14 (18.2%) |
| 0.5 | 63 | 62 | 1 | **0** | 0 | 14 (18.2%) |
| 0.6 | 63 | 62 | 1 | **0** | 0 | 14 (18.2%) |
| 0.7 | 63 | 62 | 1 | **0** | 0 | 14 (18.2%) |
| 0.8 | 63 | 62 | 1 | **0** | 0 | 14 (18.2%) |
| 0.9 | 62 | 61 | 1 | **0** | 0 | 15 (19.5%) |

By category at threshold 0.5 (good / loose / cuts / false positive / fallback):

| category | n | good | loose | cuts | false pos. | fallback | median IoU |
|---|---|---|---|---|---|---|---|
| frontal | 4 | 4 | 0 | 0 | 0 | 0 | 0.987 |
| perspective | 6 | 6 | 0 | 0 | 0 | 0 | 0.965 |
| rotation | 6 | 6 | 0 | 0 | 0 | 0 | 0.963 |
| light | 6 | 6 | 0 | 0 | 0 | 0 | 0.967 |
| low_contrast | 5 | 5 | 0 | 0 | 0 | 0 | 0.983 |
| crumple | 6 | 6 | 0 | 0 | 0 | 0 | 0.978 |
| noisy_background | 6 | 6 | 0 | 0 | 0 | 0 | 0.985 |
| hand | 4 | 3 | 1 | 0 | 0 | 0 | 0.992 |
| dark_background | 5 | 5 | 0 | 0 | 0 | 0 | 0.983 |
| partial | 5 | 5 | 0 | 0 | 0 | 0 | 0.986 |
| fills_frame | 3 | 1 | 0 | 0 | 0 | 2 | 0.013 |
| small_document | 5 | 0 | 0 | 0 | 0 | 5 | 0.914 |
| lines_background | 6 | 6 | 0 | 0 | 0 | 0 | 0.986 |
| no_document | 4 | 0 | 0 | 0 | 0 | 4 | - |
| combined | 6 | 3 | 0 | 0 | 0 | 3 | 0.957 |

Time per image (ms), frame 768x1024: prepare median 17.5, detect median 55.7, confidence median 1.0, total median 74.6, total p95 99.8.

### A3 small-area: 77 images (73 with a page, 4 without)

Raw detection (best candidate, no threshold), pages only: IoU >= 0.9 in 90.4%, nothing cut in 97.3%, median IoU 0.978, median corner error 0.40% of the diagonal (pages fully in the frame).

| threshold | used | good | loose | **cuts content** | false positive (no page) | fallback (whole frame) |
|---|---|---|---|---|---|---|
| 0.0 | 77 | 66 | 5 | **2** | 4 | 0 (0.0%) |
| 0.1 | 71 | 66 | 2 | **0** | 3 | 6 (7.8%) |
| 0.2 | 70 | 66 | 2 | **0** | 2 | 7 (9.1%) |
| 0.3 | 70 | 66 | 2 | **0** | 2 | 7 (9.1%) |
| 0.4 | 70 | 66 | 2 | **0** | 2 | 7 (9.1%) |
| 0.5 | 70 | 66 | 2 | **0** | 2 | 7 (9.1%) |
| 0.6 | 70 | 66 | 2 | **0** | 2 | 7 (9.1%) |
| 0.7 | 70 | 66 | 2 | **0** | 2 | 7 (9.1%) |
| 0.8 | 69 | 66 | 2 | **0** | 1 | 8 (10.4%) |
| 0.9 | 68 | 65 | 2 | **0** | 1 | 9 (11.7%) |

By category at threshold 0.5 (good / loose / cuts / false positive / fallback):

| category | n | good | loose | cuts | false pos. | fallback | median IoU |
|---|---|---|---|---|---|---|---|
| frontal | 4 | 4 | 0 | 0 | 0 | 0 | 0.987 |
| perspective | 6 | 6 | 0 | 0 | 0 | 0 | 0.965 |
| rotation | 6 | 6 | 0 | 0 | 0 | 0 | 0.963 |
| light | 6 | 6 | 0 | 0 | 0 | 0 | 0.967 |
| low_contrast | 5 | 5 | 0 | 0 | 0 | 0 | 0.983 |
| crumple | 6 | 6 | 0 | 0 | 0 | 0 | 0.978 |
| noisy_background | 6 | 6 | 0 | 0 | 0 | 0 | 0.985 |
| hand | 4 | 3 | 1 | 0 | 0 | 0 | 0.992 |
| dark_background | 5 | 5 | 0 | 0 | 0 | 0 | 0.983 |
| partial | 5 | 5 | 0 | 0 | 0 | 0 | 0.986 |
| fills_frame | 3 | 1 | 0 | 0 | 0 | 2 | 0.013 |
| small_document | 5 | 4 | 1 | 0 | 0 | 0 | 0.914 |
| lines_background | 6 | 6 | 0 | 0 | 0 | 0 | 0.986 |
| no_document | 4 | 0 | 0 | 0 | 2 | 2 | - |
| combined | 6 | 3 | 0 | 0 | 0 | 3 | 0.957 |

Time per image (ms), frame 768x1024: prepare median 17.8, detect median 51.9, confidence median 1.0, total median 70.9, total p95 90.4.

