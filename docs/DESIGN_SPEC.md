# Design spec (Phase 6.4)

The look of the app, for later reference. It comes from three AI design proposals (the best ideas of
each) and it is **binding**: a change here is a decision (ADR), not a tweak. Decision and reasons:
ADR-033 in `DECISIONS.md`. Where it lives in the code: `ARCHITECTURE.md` section 8l
(`lib/presentation/theme/`).

Scope: the **look only** (colours, font, shapes, spacing, component styles). Screen layouts,
features, flows and texts are not part of it.

## 1. Principles

- Everything is built from standard Material 3 widgets. Flat, **tonal** surfaces.
- **No** glow shadows, gradients, blur or glass effects, patterns or stripes in a background.
- Light or dark follows the system. **There is no theme choice in Settings.**
- Elevation 0 everywhere. Levels are told by tonal surfaces: `surface` -> `surfaceContainer` ->
  `surfaceContainerHighest`.

## 2. Where the colours come from

1. **System colours available** (`dynamic_color`, Android 12+): `lightDynamic` / `darkDynamic`,
   harmonised with `harmonized()`.
2. **Not available** (older Android or a maker without support): the fallback palettes of
   section 3 (light = pastel lime, dark = deep purple and black).
3. Widgets read **roles of the `ColorScheme`, never a hex**, so the same widget works in all three
   cases. The diagnostics screen has a line "Colours: system / fallback".

## 3. Fallback palettes (`ColorScheme` roles)

The values are checked for contrast by `test/presentation/theme/app_theme_contrast_test.dart`.
The other roles of the scheme come from `ColorScheme.fromSeed` (seed #4D6410 light, #CBBBE6 dark)
with exactly the values below on top. `surfaceTint` is transparent.

**Light (pastel lime)**

| Role | Hex |
|---|---|
| primary (text, icons, links) | #4D6410 |
| onPrimary | #FFFFFF |
| primaryContainer (filled button) | #D7EF6C |
| onPrimaryContainer | #1C2804 |
| secondaryContainer (tonal button, selected segment) | #E4F2A4 |
| onSecondaryContainer | #243306 |
| surface (screen background) | #F3F6E8 |
| surfaceContainer (cards) | #E6ECD6 |
| surfaceContainerHighest | #DBE3C6 |
| dialog (`backgroundColor` of dialogs and sheets) | #F7F8EF |
| onSurface | #1C1E14 |
| onSurfaceVariant (secondary text) | #5A5E4C |
| outline (borders of fields and choices, at least 3:1) | #7A7E66 |
| outlineVariant (decorative dividers) | #C9CDB6 |
| error / onError | #9D2F32 / #FFFFFF |

**Dark (deep purple and black, low contrast, no white)**

| Role | Hex |
|---|---|
| primary | #CBBBE6 |
| onPrimary | #2B2342 |
| primaryContainer (filled button) | #3F3658 |
| onPrimaryContainer | #E4DCF2 |
| secondaryContainer | #2A2440 |
| onSecondaryContainer | #DDD4F0 |
| surface | #121016 |
| surfaceContainer (cards) | #1A1722 |
| surfaceContainerHighest | #242033 |
| dialog | #221E2E |
| onSurface (not pure white) | #D0C9DC |
| onSurfaceVariant | #9B93AB |
| outline (at least 3:1) | #716A8C |
| outlineVariant | #3A334C |
| error / onError | #E3B4B8 / #3A1418 |

Cards: in the dark theme a 1 px `outlineVariant` border, in the light theme none. With system
colours the dialog background is `surfaceContainerHigh`.

## 4. Status colours (fixed, independent of the colour source)

`AppStatusColors`, a `ThemeExtension`, so they stay recognisable even with system colours. **The
warning stays amber in every theme** (not a strong orange, not a colour of the theme).

| Role | Light | Dark |
|---|---|---|
| warning (the "Low light" mark) | #E8B53A | #6A5738 |
| onWarning | #2C2106 | #F0E2C8 |
| warningContainer (banner or card) | #F6E4AE | #3A3226 |
| onWarningContainer | #2C2106 | #F0E2C8 |

Success and failure use the roles of the scheme (`primary` / `error`), not new colours.

## 5. The camera screens: dark "chrome" in every theme

What floats over the preview (mode bar, flash, counter, buttons) must read over any camera
picture, so it is dark and semi-transparent whatever the theme (`AppCameraColors`):

- Background of the controls area: nearly black **#0E0E10**. Chips and buttons: white 12 % over the
  black (the floating round flash button is that blend, #2B2B2D, a little transparent). Text and
  icons: **#E8E8EA**.
- Selected element (mode segment, flash On, the Done button):
  light fallback **#D7EF6C** with text #1C2804; dark fallback **#5C4D82** with text #E4DCF2; with
  system colours the `primaryContainer` / `onPrimaryContainer` of the **dark** scheme.
- The low light mark and bar use `warning` / `onWarning` and `warningContainer` /
  `onWarningContainer` of section 4.
- Screens that are not the camera follow the theme as usual.

## 6. Font: Noto Sans from assets

- Noto Sans (Greek included) as **files in `assets/fonts/`**, family `NotoSans`: Regular 400,
  Medium 500, SemiBold 600 (hinted TTF, the whole fonts). **No package, no download**: the app is
  offline-first and private. Licence: SIL OFL 1.1 (`assets/licenses/notosans_OFL.txt`).
- Type scale (size / line height):

| Style | Size / line | Weight | Used for |
|---|---|---|---|
| headlineSmall | 26 / 32 | 600 | screen titles |
| titleLarge | 22 / 28 | 500 | app bar, dialogs |
| titleMedium | 18 / 24 | 600 | cards, sections |
| bodyLarge | 16 / 24 | 400 | |
| bodyMedium | 15 / 22 | 400 | main text |
| bodySmall, labelSmall | 13 / 18 | 400 | helper text |
| labelLarge | 15 / 20 | 600 | buttons |

The system text scale is respected (it is not blocked).

## 7. Shapes (one set for every theme)

| Element | Shape |
|---|---|
| Buttons, segmented buttons, chips, switches | stadium (fully rounded) |
| Text fields | radius 16 |
| Cards | radius 24 |
| Dialogs and bottom sheets | radius 28 |
| Page thumbnails | radius 12 |

## 8. Spacing and sizes

- Scale: 4, 8, 12, 16, 24, 32, 48 (`AppSpacing`).
- Screen margin 24 horizontal. Gap between cards 12, between sections 24.
- Button height 56. Minimum touch target 48 x 48. No shadow (elevation 0).

## 9. Components

- **FilledButton** = `primaryContainer` / `onPrimaryContainer` (a pastel fill, not a dark `primary`
  fill). **Tonal** = `secondaryContainer` (`AppButtonStyles.tonal`, because the theme of the filled
  button would otherwise reach the tonal one). **OutlinedButton** = `outline` border, `primary`
  text. **TextButton** = `primary` text.
- **SegmentedButton**: selected = `secondaryContainer`, `outline` border, stadium.
- **Switch / Radio / Checkbox**: standard Material 3 with the roles of the scheme.
- **Fields**: `outline` border, `primary` when focused, radius 16.
- **Dialogs**: `dialog` background, radius 28, title `titleLarge`, `TextButton` actions.
- **Capture button**: outer ring 72 dp, 4 dp thick, inner disc 56 dp, scale 0.94 while pressed. The
  "busy" state of Phase 6.3 (spinner, "Taking photo...") stays, in the new colours. Ring colour
  #E8E8EA on the dark chrome. No glow.
- **Icons**: the icons built into Flutter, the `_rounded` variants where they exist, to match the
  rounded shapes. No icon package.

## 10. Known deviations and notes

- The dark fallback selection colour of the camera chrome (#5C4D82) measures 2.61:1 against the
  chrome #0E0E10, below the 3:1 of a UI component. The label inside it passes (higher than 4.5:1).
  Kept as specified; noted in `PHASE_6_4_VALIDATION.md` for the phone check.
- `dynamic_color` 1.8.1 is used, not 2.x: version 2 returns the `ColorScheme` of the `material_ui`
  package, a different type from the one of this Flutter's `material.dart` (see ADR-033).
