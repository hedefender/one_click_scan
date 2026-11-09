# Documents index

Start with the root [`README.md`](../README.md), then [`ARCHITECTURE.md`](ARCHITECTURE.md) and
[`DECISIONS.md`](DECISIONS.md). The phase documents are the record of how the app was built.
Some are written in Greek because they are checklists for the person who tests on a phone.

## Start here

| Document | What it is |
|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | Layers, data flow, one section per feature area (camera, OCR, PDF, mail, flow, crop, light) |
| [`DECISIONS.md`](DECISIONS.md) | 33 numbered decisions (ADR) with their reasons |
| [`ROADMAP.md`](ROADMAP.md) | Phases, their state, open decisions, backlog, and the polish list |
| [`DESIGN_SPEC.md`](DESIGN_SPEC.md) | The look of the app (Phase 6.4): palettes, status colours, camera chrome, font, shapes, components |
| [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) | Third-party components and their licenses |

## Mail

| Document | What it is |
|---|---|
| [`MAIL_PROVIDERS.md`](MAIL_PROVIDERS.md) | SMTP settings and app-password steps per provider (Gmail, Outlook.com, Yahoo) |
| [`MAIL_OAUTH_PLAN.md`](MAIL_OAUTH_PLAN.md) | Research for the future OAuth sign-in (nothing implemented) |

## OCR, PDF and image spikes (numbers behind the decisions)

| Document | What it is |
|---|---|
| [`OCR_SPIKE_RESULTS.md`](OCR_SPIKE_RESULTS.md) | OCR engine comparison and tuning on synthetic documents |
| [`OCR_LANGUAGE_PACKS.md`](OCR_LANGUAGE_PACKS.md) | Which language packs exist and what is confirmed |
| [`PDF_SPIKE_RESULTS.md`](PDF_SPIKE_RESULTS.md) | Searchable-PDF spike: text layer options on a phone |
| [`IMAGE_SPIKE_RESULTS.md`](IMAGE_SPIKE_RESULTS.md) | Crop and perspective detectors, contrast, shadow removal, and the light metric |
| [`image_spike_data/`](image_spike_data/README.md) | Reports and tables of the image spike (synthetic pictures only) |
| [`samples/`](samples) | Two synthetic sample documents for the OCR |

## Phase documents

`PHASE_<n>_VALIDATION.md` lists what changed for the user and the checks done on the emulator,
plus the manual checks for a real phone: [0](PHASE_0_VALIDATION.md), [0.5](PHASE_0_5_VALIDATION.md),
[1](PHASE_1_VALIDATION.md), [1.1](PHASE_1_1_VALIDATION.md), [1.2](PHASE_1_2_VALIDATION.md),
[1.5](PHASE_1_5_VALIDATION.md), [1.6](PHASE_1_6_VALIDATION.md), [2](PHASE_2_VALIDATION.md),
[2.1](PHASE_2_1_VALIDATION.md), [3](PHASE_3_VALIDATION.md), [4](PHASE_4_VALIDATION.md),
[5](PHASE_5_VALIDATION.md), [6.0](PHASE_6_0_VALIDATION.md), [6.1](PHASE_6_1_VALIDATION.md),
[6.2](PHASE_6_2_VALIDATION.md), [6.2.1](PHASE_6_2_1_VALIDATION.md), [6.3](PHASE_6_3_VALIDATION.md), [6.4](PHASE_6_4_VALIDATION.md). The latest is the best example of the format.
[`PHASE_0_PLAN.md`](PHASE_0_PLAN.md) is the original plan of the skeleton phase.

## Historical

| Document | What it is |
|---|---|
| [`DATA_CONTRACT_V1.md`](DATA_CONTRACT_V1.md) | JSON contract, superseded: Scan produces no JSON (ADR-008) |
| [`CLAUDE_CODE_PHASE_0.md`](CLAUDE_CODE_PHASE_0.md) | The Phase 0 instructions given to the coding assistant (Greek) |

The rules the coding assistant follows are in [`../CLAUDE.md`](../CLAUDE.md).
