# interface_candidates

**Candidate** Interface Kit components, small and plain-Material, derived from
what the six demo apps in this repository and a larger SlashBuilder app actually
duplicate. This is not the Interface Kit. The real Interface Kit is a separate
Kit and stays untouched; its maintainers decide what, if anything, is promoted.
Nothing here is published (`publish_to: none`).

Evidence: the table below says how many of the six demo apps (and, where known,
the larger app) each component would replace.

## What each component replaces

"Built" means I found a hand-built version in the current source. "Wanted" means
the app's author asked for it. Anything with fewer than 3 real users is marked
THIN: it is a candidate, not a recommendation.

| Component | Replaces (apps, of 6) | Replaces (larger app) | Support |
|---|---|---|---|
| `EmptyState` | Built in notepad (`empty-state`), launcher, render-queue; minesweeper has a one-line "No wins yet". An earlier count listed stopwatch as a fifth user, but its code has none. | 5 near-identical `_empty()` methods | Strong |
| `LoadingView`, `AsyncStateView<T>`, `ErrorView`, `ViewState<T>` | Launcher's `snap == null ? spinner : rows.isEmpty ? empty : list` ladder. The other apps have no async load. | `CircularProgressIndicator` pasted 7 times; 15 screens hand-roll an error state; 9 calls spell the error banner two ways; `view_state.dart` used by 1 screen | Strong from the larger app, 1 app |
| `PageScaffold` | All 6 (`Scaffold` + `AppBar(title: manifest.name, actions)`); stopwatch adds a footer and tabs, notepad is master/detail with a status bar | its own app-bar widget in 27 files vs raw `AppBar` in 21 | Strong |
| `StatusBanner` | Wanted by 5 (all but calculator). Built in launcher (`_Banner`) and render-queue (venue banner, `_OrphanBanner`); notepad and minesweeper built one in round 1 and now use the companion's `NotesBanner` | its own banner widget, 239 uses in 30 files | Strong |
| `showToast` | **Built in none**; wanted by 4 (minesweeper, notepad, stopwatch, render-queue) | `SnackBar` 50 uses in 16 files; `_toast` rewritten 3 times | Strong from the larger app; apps are demand only |
| `StatusDotRow` | Launcher's row has a dot. Render-queue's job tile uses a chip, notepad's note row has the overflow menu and no dot | Services row: named in the original request, **not read** | THIN (1 app). The shape is the union of three different rows. |
| `confirmDialog`, `promptDialog` | Notepad only (delete, rename) | not counted | THIN (1 app) |
| `SaveStatusChip` | Notepad only | none | THIN (1 app) |
| `relativeTime` | Launcher listed a "relative-time formatter"; its code is `formatUptime`, a **Duration** formatter ("1h 02m"), which this does not replace | none | THIN (1 app, and the evidence is a different function) |

Not duplicated here, on purpose: `ModeBadge` and `NotesBanner` stay in
the App Context Kit's Flutter companion. `NotesBanner` could be rebuilt on `StatusBanner`:
each note becomes `StatusBanner(severity: <1:1 map of NoteSeverity>, message:
note.text, label: 'Note' for info, onDismiss: ...)`; the dismissed-set state stays in
`NotesBanner` (this banner is controlled). Colours differ slightly, so its colour
tests would move to the theme seam below.

## Theming seam

Every colour and every text style comes from `Theme.of(context)`
(`ColorScheme`, `TextTheme`). The only literal numbers are spacing and sizes in
`lib/src/spacing.dart` (`kGapS`, `kMinTapTarget`, `kWideBreakpoint`, ...) plus a few
structural ones noted in comments (banner and footer height caps, the AppBar title
text-scale clamp of 1.34 that mirrors Flutter's own, snackbar durations). The one
font attribute set by hand is `FontWeight.bold` for the severity word.

Two files are the seam:

* `lib/src/severity.dart` maps `Severity` (info, success, warning, error) to icon,
  word and container colours. Material's `ColorScheme` has no success or warning
  role, so success uses `primaryContainer` and warning uses `tertiaryContainer`
  (the companion's `NotesBanner` already does the second). That is a placeholder
  for the design system's tone tokens, not a design decision.
* `lib/src/spacing.dart` is the spacing scale.

Tests prove the seam: each themed widget is pumped with a purple-seeded
`ColorScheme` (not Flutter's default) and light and dark, and asserts the widget
painted that scheme's roles.

## Accessibility contract

Every component, enforced by tests (`test/*_test.dart`):

1. **Labels and semantics.** Interactive things have an accessible name (visible
   label, or tooltip for icon buttons). Titles are headings. Decorative icons are
   excluded from semantics. Banners and toasts read as "Warning: message", once.
2. **Announced changes.** `StatusBanner` (not info), `ErrorView`, `LoadingView`, a
   `showToast` and a not-saved `SaveStatusChip` are live regions.
3. **Never colour alone.** Severity has an icon and a word; a dot has its own shape
   and a required `statusLabel`; save state has an icon and a word.
4. **48 dp targets.** Checked with Flutter's `androidTapTargetGuideline` and
   `labeledTapTargetGuideline`; text contrast with `textContrastGuideline`, light
   and dark.
5. **Text scale 2.0.** Each component is pumped at 2.0 on a small screen and must not
   overflow (an overflow is an exception, which fails the test). Message blocks
   scroll; banner and footer slots are capped (40% and 25% of the page) and scroll
   inside the cap; titles ellipsise.
6. **Focus order.** Master and detail panes are separate focus groups (Tab walks the
   whole list, then the detail); a destructive confirm focuses Cancel, not the
   destructive button.

Caveats: `flutter_test` renders the Ahem font, about twice as wide as real text,
so the 2.0 tests are a worst case. Flutter's own `AppBar` clamps title text scale to
1.34, so page titles do not reach 2.0. No screen reader was run; this is semantics
tree and guideline testing only.

## Promoting a component into the real Interface Kit

The rule is "extracted 1:1 from the screens that duplicated it": a candidate is
promoted only when at least 3 real screens duplicate it and it needs nothing from
the app. Components marked THIN above do not pass today. Promotion is the Interface
Kit maintainers' call and happens in that Kit, not here: the component's code and
tests are copied over, its Theme lookups are mapped onto the design system's tokens,
and the hand-built versions in the apps are deleted in the same change.

## What is NOT included, and why

* **Segmented control**: Material's `SegmentedButton` already does it; one app.
* **Keypad**: calculator's `FilledButton.tonal` set is a button style set, not a component.
* **System notification**: stopwatch's `osascript` / `notify-send` is platform code.
* **Mode badge, notes banner**: stay in the App Context Kit's Flutter companion.
* **Text roles** (the larger app's 228 hand-written `TextStyle`s): the design system's job, not the Interface Kit's.
* **The larger app's other generic-looking widgets** (`timeline`, `message_list`, ...): not read.
* **Tabs and drawers in `PageScaffold`**: stopwatch's `TabBar` in the app bar is not
  covered (one app); nested navigation is a navigation shell, a different component.
* **Localisation**: strings are English, with labels overridable where cheap.
* **Golden tests**: they need the design system's fonts and theme.
* **A dismissing banner**: `StatusBanner` is controlled; the caller stops building it.

## Run it

```sh
flutter pub get
flutter analyze
flutter test                      # includes test/catalog_test.dart, which walks the whole catalog
```

To look at the catalog (every component in every state, with light/dark and 1x/2x
text buttons in the app bar), generate a runner once. The generated folders are
git-ignored here and verified to build for macOS:

```sh
flutter create --platforms=macos .      # pick your platform; delete the runner folders afterwards
flutter run -d macos -t example/main.dart
```

Test floor: `lib/` declares the real Interface Kit's floor (Flutter 3.27, Dart 3.6) but was
only built and tested on Flutter 3.41.9. The tests use newer semantics APIs
(`flagsCollection`, `Tristate`) and need a current stable Flutter.
