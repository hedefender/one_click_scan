### A3 pure Dart: 77 images (73 with a page, 4 without)

Raw detection (best candidate, no threshold), pages only: IoU >= 0.9 in 89.0%, nothing cut in 95.9%, median IoU 0.976, median corner error 0.48% of the diagonal (pages fully in the frame).

| threshold | used | good | loose | **cuts content** | false positive (no page) | fallback (whole frame) |
|---|---|---|---|---|---|---|
| 0.0 | 77 | 65 | 5 | **3** | 4 | 0 (0.0%) |
| 0.1 | 67 | 64 | 2 | **1** | 0 | 10 (13.0%) |
| 0.2 | 63 | 62 | 1 | **0** | 0 | 14 (18.2%) |
| 0.3 | 62 | 61 | 1 | **0** | 0 | 15 (19.5%) |
| 0.4 | 62 | 61 | 1 | **0** | 0 | 15 (19.5%) |
| 0.5 | 62 | 61 | 1 | **0** | 0 | 15 (19.5%) |
| 0.6 | 62 | 61 | 1 | **0** | 0 | 15 (19.5%) |
| 0.7 | 62 | 61 | 1 | **0** | 0 | 15 (19.5%) |
| 0.8 | 62 | 61 | 1 | **0** | 0 | 15 (19.5%) |
| 0.9 | 62 | 61 | 1 | **0** | 0 | 15 (19.5%) |

By category at threshold 0.5 (good / loose / cuts / false positive / fallback):

| category | n | good | loose | cuts | false pos. | fallback | median IoU |
|---|---|---|---|---|---|---|---|
| frontal | 4 | 4 | 0 | 0 | 0 | 0 | 0.981 |
| perspective | 6 | 6 | 0 | 0 | 0 | 0 | 0.966 |
| rotation | 6 | 6 | 0 | 0 | 0 | 0 | 0.962 |
| light | 6 | 5 | 0 | 0 | 0 | 1 | 0.968 |
| low_contrast | 5 | 5 | 0 | 0 | 0 | 0 | 0.984 |
| crumple | 6 | 6 | 0 | 0 | 0 | 0 | 0.980 |
| noisy_background | 6 | 6 | 0 | 0 | 0 | 0 | 0.987 |
| hand | 4 | 3 | 1 | 0 | 0 | 0 | 0.990 |
| dark_background | 5 | 5 | 0 | 0 | 0 | 0 | 0.984 |
| partial | 5 | 5 | 0 | 0 | 0 | 0 | 0.987 |
| fills_frame | 3 | 1 | 0 | 0 | 0 | 2 | 0.009 |
| small_document | 5 | 0 | 0 | 0 | 0 | 5 | 0.915 |
| lines_background | 6 | 6 | 0 | 0 | 0 | 0 | 0.985 |
| no_document | 4 | 0 | 0 | 0 | 0 | 4 | - |
| combined | 6 | 3 | 0 | 0 | 0 | 3 | 0.958 |

Time per image (ms), frame 1536x2048: prepare median 27.8, detect median 57.8, confidence median 1.0, total median 87.5, total p95 109.5.

