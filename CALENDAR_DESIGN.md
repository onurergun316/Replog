# Replog Calendar — Design Bible

The Calendar tab: every training day at a glance, any day's detail one tap away, and any
range of days summarizable by selecting them. Grounded in a 20-product survey (Hevy, Strong,
Jefit, Fitbod, Alpha Progression, Boostcamp, Caliber, Ladder, Gravitus, FitNotes, Apple
Fitness, Whoop, Strava, Garmin Connect, Oura, Nike Training Club, Peloton, MyFitnessPal,
StrengthLog, GymBook/Setgraph) and Replog's own design system.

## What the market taught us

**Common patterns (what ≥60% of surveyed apps do):**
- The **month grid is the canonical form** (12/20 confirmed) — lists and charts orbit it.
- The plurality marker is a **single binary dot/circle in one brand color** on trained days.
  Graded encodings (heat maps, rings, volume bubbles) are a strong minority — but every
  strong pattern uses **one encoding per cell**, never two.
- **Tap a day → that day's workouts** is universal wherever a calendar exists.
- **Streaks sit adjacent to the calendar** (header/footer), essentially never inside cells.
- Range statistics usually live in separate report screens — **only Alpha Progression makes
  the calendar itself the range selector**, and it's the most-loved differentiator found.

**Differentiators worth stealing:** calendar-as-report-generator (Alpha Progression);
planned **future** days on the same grid as history (Garmin's signature, Strava's most
requested feature); retro-visible partial days.

**Anti-patterns to avoid:** undifferentiated markers (Apple ring-fill every day → can't spot
real workouts; Garmin's one-color-for-everything complaints), burying the calendar behind
taps or paywalls (Apple, Strava), and splitting planned days from done days into different
screens (Strava's top community merge request).

## Product decisions (v1)

1. **A real tab.** Calendar takes Progress's slot (iPhone tab bars hold 5; a 6th folds into
   a system "More" list — verified on this SDK). Progress moves behind a "Progress & Trends"
   card at the top of Profile. Bar: **Today · Plans · Library · Calendar · Profile**.
2. **Month grid, paged horizontally**, one month per page, swipe or chevrons. Sunday-first
   columns (S M T W T F S), matching the Today week strip and `StreakEngine`'s weeks.
3. **One encoding per cell**, drawn from the week strip's exact vocabulary
   (`WeekStripView` is the small sibling of this grid):
   - **Completed day** → 30 pt accent-filled circle + white check.
   - **Today** → 2 pt accent ring.
   - **Scheduled future day** (from the plans' weekdays; Extras are day-less and never
     mark the grid) → 4 pt accent dot under the number.
   - **Selected day(s)** → soft accent chip behind the cell (`accentSoft`, radius 12).
   - Adjacent-month days render dimmed (`text3`) and unmarked.
4. **Streaks live in the header, not in cells**: the day-streak flame + week streak, from
   `StreakEngine`, in the same capsule style as Today's flame.
5. **Tap a day → that day, below the grid** (no sheet — selection must survive browsing):
   date headline, that day's logged exercises (name, top set, e1RM, set-by-set breakdown —
   the `StatDetailSheet` visual treatment), bodyweight/readiness if logged that day, and an
   honest empty state for rest days.
6. **Long-press + drag → multi-day selection → averages.** The Alpha Progression move:
   selecting N days replaces the day detail with a **range summary**: span, training days,
   sets, reps, volume (kg/lb), best lift, and per-training-day averages. Selection
   accumulates across months; "Clear" resets to today. Multiple finishes in one day still
   count that day once — days are binary, matching the streak engine.
7. **Month footer stat line**: "N workouts · V volume" for the visible month.

## Interaction spec

- **Tap** a cell: select exactly that day (replaces any range). Tapping the sole selected
  day deselects back to today. `.sensoryFeedback(.selection)`.
- **Long-press (~0.3 s) then drag** across cells: the first cell's inverted state applies to
  every cell crossed (Photos-style free-set). A medium impact marks the arm-moment; a
  selection tick per cell crossed.
- The long press is a **`UILongPressGestureRecognizer` via `UIGestureRecognizerRepresentable`**
  on the grid — NOT a SwiftUI `LongPressGesture`. It participates in UIKit's gesture
  arbitration, so scrolling/paging wins when the finger moves early and the press wins on a
  genuine hold. (The reorder-lift bug taught this repo that SwiftUI gestures don't arbitrate
  with UIKit's — see `DragToReorder.swift`. This is the sanctioned bridge.)
- While selecting, both the vertical scroller and the month pager are `.scrollDisabled`.
- Cell under the finger = O(1) coordinate math over the grid's frame (7 columns × 6 rows,
  spacing folded in) — no per-cell frame collection.
- **Month paging**: horizontal `ScrollView` + `LazyHStack` + `.scrollTargetLayout()` +
  `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)`, each page
  `containerRelativeFrame(.horizontal)`. Not `TabView(.page)` — its internal pan can't be
  disabled during selection.
- **Date math**: explicit Gregorian calendar with `firstWeekday = 1`; grids built from
  `dateInterval(of:)`, days iterated with `date(byAdding: .day)` (never +86 400 s); a fixed
  42-cell (6-row) page so month heights never jump; "today" refreshed on day change.
- **Accessibility**: every cell is a button with a full label ("Monday, June 8, workout
  completed"); tap-to-select is the complete VoiceOver path (range selection is a
  power-user shortcut, not the only route to any information).

## Data honesty (what v1 shows vs doesn't)

Powered by existing data: done-day markers (`doneDates` ∪ `HistoryEntry` days), per-day
exercise detail with full sets (`HistoryEntry.setsJSON`), range totals/averages (the same
math `WeeklyReportComposer` uses), streaks, scheduled-future dots, per-day bodyweight and
readiness.

**Not stored today — deferred to v2, never faked:** the finished workout's *name* and
*duration* (the live session is deleted on finish; history is per-exercise), per-set RPE,
multiple distinct workouts in one day (a day is one identity). v2 backlog, in pattern-
justified order: persist workout name + duration on finish → retro-logging past days from
empty cells (Hevy/Caliber) → volume-intensity cell tint as an optional second read
(Jefit/Whoop) → year-at-a-glance zoom (Hevy) → muscle/exercise calendar filters (FitNotes).

## Layout anatomy

```
┌────────────────────────────────────────┐
│ CALENDAR                    🔥 12 · 3w │  eyebrow + screenTitle + streak capsules
│ ┌────────────────────────────────────┐ │
│ │  ‹   June 2026   ›                 │ │  month header (chevrons + swipe)
│ │  S  M  T  W  T  F  S               │ │  weekday row (text3, 11 heavy)
│ │  ·  ✓  2  ✓  4  ●  6              │ │  42-cell grid, WeekStripView vocabulary
│ │  …  (6 rows)                       │ │
│ │  N workouts · V kg this month      │ │  month footer line
│ └────────────────────────────────────┘ │  ← one cardSurface
│ TUESDAY, JUNE 2 — or — 5 DAYS SELECTED │  SectionHeader eyebrow
│ [day detail rows | range summary card] │
└────────────────────────────────────────┘
```

All tokens from `DesignSystem/`: `Color.bg` page, `cardSurface()` cards, SF Rounded type
scale, `Pill`, `SectionHeader`, capsule chips, `sensoryFeedback` conventions. No new colors,
no new typography.
