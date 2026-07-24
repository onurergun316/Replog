# Replog Progress — Design Bible

The Progress tab: every number the app can honestly derive from what you logged, arranged as an
onion you peel by tapping. Companion to `CALENDAR_DESIGN.md`; same house rules, same tokens.

Written after the first real training week exposed seven defects — blank charts, a lone bar stranded
at the right edge, phantom navigation pushes, and bodyweight movements worth zero — this document is
the spec those fixes are built against, so the reasoning survives the commits.

---

## 1. Principles

1. **Never blank.** A chart with data somewhere must render something. One session is a picture of a
   session, not a failed trend line.
2. **Never misleading.** Time ascends left→right and starts where the athlete started. A bar's height
   means what the axis says it means. No stacking two series that aren't a stack.
3. **Every number has one home.** "Total weight lifted" per set / session / day / week / muscle /
   exercise each live on exactly one screen; everything else links to it. No metric is computed twice.
4. **Honest about what isn't known.** Stretching earns no tonnage. Band tension is unknowable and
   excluded. Correlations aren't drawn at n=3.
5. **Pure logic in `Domain/`, tested.** Views draw; they never derive.

---

## 2. Effective load — the single tonnage seam

Every volume figure in the app used to be a literal `set.w * set.r`, in ten places. A bodyweight
movement logs `w = 0`, so pull-ups, dips and push-ups were worth **zero** tonnage, had an estimated
1RM of zero, and could never appear in Strength or PRs.

**The rule.** For a set `(w, r)` of exercise `x` performed on date `d`:

```
effectiveKg = f(x) × BW(d) + w      if x is bodyweight-loaded
effectiveKg = w                     otherwise
```

- `f(x)` — the movement's %BW factor (§3). `w` on a bodyweight move is *added* load: a dip belt or
  vest, never the body itself.
- `BW(d)` — the athlete's bodyweight in effect on that date: the latest `BodyweightEntry ≤ d`,
  falling back to the earliest. Historical tonnage uses the bodyweight you *were*.
- **Bodyweight-loaded** = `equipment == .bodyOnly || equipment == nil`, **and**
  `category ∈ {strength, plyometrics}`. This mirrors `PatternMapping`'s existing rule that missing
  equipment counts as bodyweight.
- **Timed holds** (the verified static∩strength exIds — Plank, Side Bridge, the isometrics): the
  logged `reps` field holds *seconds*, so `effVolume = f × BW × seconds / 3` — one rep-equivalent per
  3 s of tension. Excluded from rep counts and the rep-range mix, where "12" would mean nothing.
- **Stretching and cardio earn no tonnage at all.** That is 85 of the 188 bodyweight-ish catalog
  entries; crediting them would be the dishonest shortcut.

**Computed at read time, never baked into history.** Aggregators take an injected
`LoadResolver` closure — the same dependency-injection shape `muscleShares` already uses for its
catalog lookup. Three consequences, all good: existing history is credited **retroactively with no
migration**, tuning the factor table re-values the past automatically, and `HistoryEntry.e1rm` stops
being the source of truth for analytics (which recompute from effective load instead).

---

## 3. The %BW factor table

Grounded in force-plate ground-reaction-force studies (Ebben et al. 2011, JSCR; Gouvali & Boudolos
2005) and Dempster/de Leva segment masses — head+neck ≈8% BW, head-arms-trunk ≈68%, both legs ≈32%,
shanks+feet ≈12%, per-arm ≈5%. Values deliberately **err low**, matching the app's existing
"starting loads err LOW" philosophy.

Resolution order: **per-exId override → name-keyword family → primary-muscle facet fallback**.

| # | Family (keywords) | f | Rationale |
|---|---|---|---|
| 1 | Push-up standard/wide/close/clock/one-arm | 0.64 | Measured hand GRF ≈64% BW in the plank-arm position |
| 2 | Push-up feet-elevated / decline | 0.70 | GRF shifts toward the hands with foot elevation (≈70–74%); err low |
| 3 | Push-up hands-elevated / incline | 0.45 | Hands-elevated GRF ≈41–55% by box height; midpoint |
| 4 | Handstand push-up | 0.90 | Near-total BW on the hands; wall-braced feet carry ~5–10% |
| 5 | Pike push-up | 0.75 | Between standard and handstand as the hips rise over the hands |
| 6 | Pull-up / chin-up / muscle-up / scapular pull-up | 0.95 | Whole body raised, minus the gripping hands and forearms |
| 7 | Dip (full suspension) | 0.95 | Same full-suspension logic as the pull-up |
| 8 | Bench / chair dip | 0.60 | Floor-supported legs offload ~35–40% BW to the feet |
| 9 | Inverted / body row | 0.60 | Hand GRF ≈50–75% BW across typical torso angles; midpoint |
| 10 | Squat / lunge / split squat / step-up | 0.75 | Moved mass = HAT (~68%) + partial thighs; shanks stay grounded |
| 11 | Pistol / sissy squat | 0.80 | Greater displaced share on a single-leg or knee lever |
| 12 | Jumps & plyometrics | 1.00 | The entire body leaves the floor every rep |
| 13 | Glute bridge / butt lift / hip raise | 0.45 | Pelvis-trunk-thigh fraction lifts; the shoulders bear the rest |
| 14 | Back extension / hyperextension / superman | 0.50 | HAT pivots at the hip while the pad supports the pelvis |
| 15 | Nordic / natural / floor glute-ham raise | 0.60 | HAT on a knee-pivot lever, partially supported through the ROM |
| 16 | Sit-up / jackknife / V-up | 0.40 | HAT engaged, but the lumbar pivot carries only part through the ROM |
| 17 | Crunch / heel toucher | 0.20 | Only the head (~8%) and upper thoracic segment leave the floor |
| 18 | Leg raise / reverse crunch / knee tuck / flutter kick | 0.30 | Both legs ≈32% BW; bent-knee variants less — err low |
| 19 | Core dynamic misc (mountain climber, russian twist, dead bug, air bike) | 0.25 | Between crunch and leg-raise segment masses; partial ROMs |
| 20 | Single-limb isolation (kickback, fire hydrant, leg lift) | 0.15 | One limb's segment mass (~16%) through a partial ROM |
| 21 | Standing bodyweight calf raise | 0.95 | Whole body minus the feet rises on the ankle lever |
| 22 | Neck | 0.08 | Head + neck ≈8.1% BW (Dempster) |
| 23 | Timed holds (per-exId, see below) | — | Credited as `f × BW × seconds/3` |

**Per-exId overrides.** Plank 0.60 · Side Bridge 0.55 (load-distribution studies put ~55–65% of BW on
the upper supports in prone and side bridges) · Isometric Chest Squeezes 0.10 (arm-on-arm force,
minimal displaced mass) · Isometric Neck 0.08 · Prone Manual Hamstring 0.35 · Gorilla Chin Crunch
0.95 (suspension governs).

**Facet fallback** for unmapped bodyweight strength/plyo entries, by primary muscle:
quads/glutes/hamstrings/adductors → 0.75 · chest/triceps/shoulders (push) → 0.64 ·
lats/middle back/biceps (pull) → 0.95 · abdominals/lower back → 0.30 · catch-all → 0.50.

**Exclusions.** `category ∈ {stretching, cardio}` → no tonnage. Bands → typed kg only; band tension
is unknowable and is never guessed.

**Required coverage test.** Every bodyweight-loaded strength/plyo catalog entry resolves to
`f ∈ [0.05, 1.0]`; every hold exId resolves `isTimedHold == true`; no stretching or cardio entry
resolves a factor at all.

---

## 4. Chart law

**X-domain policy.** (1) Time ascends left→right; the right edge is the end of the current bucket.
(2) The lower bound is `max(windowStart, bucketFloor(firstActivity))` — **leading emptiness from
before the athlete existed never renders.** This is the fix for the first training week appearing
stranded at the far right with eleven invisible bars to its left. (3) Interior and trailing zero
buckets *do* render: a skipped week is information. (4) No artificial padding. (5) When the account is
younger than the chosen window, caption it ("since Jul 20"). Pin with `.chartXScale(domain:)`.
`firstActivity` is per context: training charts use the earlier of the first `HistoryEntry` and the
first done date; Body uses the first `BodyweightEntry`.

**Marks.** `.monotone` interpolation everywhere (replacing `.catmullRom`, which overshoots on sparse
data). **Every line chart carries `PointMark`s** — this is the never-blank guarantee, because a
`LineMark` with one point paints nothing at all. Bars: `width: .ratio(0.6)`, `cornerRadius(3)`,
baseline always zero. e1RM and bodyweight lines: `includesZero: false` plus a **minimum y-span**
(±5% of the mean for e1RM, ≥2 kg for bodyweight) so a flat series doesn't collapse to a line of noise.
Average and target rules are 1 pt `Color.text3` `RuleMark`s with a trailing label. Area washes ≤22%.

**Never stack what isn't a stack.** Two `BarMark`s at the same x stack by default in Swift Charts, so
drawing `scheduled` and `done` that way renders a perfect 3-of-3 week as a half-filled bar of height
6. Adherence uses explicit `yStart`/`yEnd` spans: a `Color.track` backdrop `0…scheduled` with a
`ramp(0)` overlay `0…done`.

**Ramp discipline** (`ProgressPalette`, monochrome by house rule). `ramp(0)` = the subject ·
`ramp(1–2)` = second and third series, hard cap of three line series · `ramp(3–5)` = donut and stack
segments only · `Color.track` = backdrop and "Other" · `Color.up`/`.down` = status only, always paired
with an icon or sign so colour is never the sole carrier. De-emphasised bars standardise on `ramp(2)`.

**Units.** All math in kg; every axis and log string renders through `Formulas.displayWeight` /
`formatWeight`. No hardcoded "kg" anywhere.

**Interaction.** Every L2/L3 time chart gets `.chartXSelection` scrubbing with a snapped `RuleMark`
and a compact annotation, `.sensoryFeedback(.selection)` on snap, and ≥44 pt hit targets. Every value
reachable by scrubbing is **also** reachable in the list below the chart — never tooltip-gated.
Accessibility: marks carry labels and values; each screen's primary chart ships an audio graph.

---

## 5. The sparse-data ladder

Tiers by `n` = points in the rendered series. This is a contract, not a suggestion — each tier is
tested.

| Tier | Condition | What renders |
|---|---|---|
| **T0** | nothing in the store | The existing guidance empty state |
| **T1** | nothing in the window, but data all-time | **Auto-widen**: render all-time with the caption "Nothing in the last N weeks — showing all time". Never an empty card when data exists somewhere |
| **T2** | n = 1 | `PointMark` + a dashed reference at the value + "baseline — log it again to see a trend". On per-exercise screens, swap to that session's **set-by-set bar chart** |
| **T3** | n = 2–4 | Line with visible points, plus a delta chip (`TrendArrow` + signed %) versus previous |
| **T4** | n ≥ 5 | Full styling: average rules, PR annotations, scrubbing |

Stat tiles are computable at n=1 and every screen leads with them, so **no screen is ever
number-less**. A bar chart with one bucket shows one labelled bar with no leading emptiness; a donut
with one slice renders with an explanatory caption.

---

## 6. The onion

Every path reaches ≥3 layers; most reach 4, several 5. All transitions are **pushes** inside the
Progress `NavigationStack` — zero new sheets. `✎` = changed, `★` = new.

```
L1  ProgressHomeView ✎     [Calendar · Strength · Volume · Muscles · Consistency · Body]
├── Calendar    ─▶ L2 CalendarView ✎ ─▶ L3 day detail (DayLogCard ★) ─▶ L4 ExerciseDetail
├── Strength    ─▶ L2 Strength ✎     ─▶ L3 ExerciseDetail ✎          ─▶ L4 session log
├── Volume      ─▶ L2 Volume ✎       ─▶ L3 WeekDetailView ★ ─▶ L4 TrainingDayView ★ ─▶ L5 Exercise
│                                    ─▶ L3 VolumeStatDetail ★ (total · avg · sets)
│                                    ─▶ L3 LoadSplitDetail ★
│                                    ─▶ L3 RepRangeDetail ★
├── Muscles     ─▶ L2 Balance ✎      ─▶ L3 MuscleDetail ✎   ─▶ L4 ExerciseDetail ─▶ L5 session log
│                                    ─▶ L3 ForceSplitDetail ★
├── Consistency ─▶ L2 Consistency ✎  ─▶ L3 WeekDetailView ★ ─▶ L4 TrainingDayView ★
└── Body        ─▶ L2 Body ✎         ─▶ L3 BodyweightHistoryView ★ ─▶ L4 TrainingDayView ★
```

**Every headline opens.** A number a user can read but not question is a dead end, so each L2
summary tile and each part-to-whole card carries a route into what it is made of. All four of those
L3 breakdowns are views of one derivation — `ProgressAnalytics.exerciseContributions` — so a
headline and its breakdown cannot disagree about a total (pinned by test). The route carries the
window as `days: Int?`, because a breakdown that silently described a different span than the tile
that opened it would be worse than no breakdown at all.

**Canonical home for every "total weight lifted per X"** — per set → the L4 log expansion · per
session and per day → `TrainingDayView` · per week → `WeekDetailView` · per month and per arbitrary
range → the Calendar's month footer and range summary · per muscle → `MuscleDetailView` · per
exercise → `ExerciseDetailView` · per equipment, force or rep-range → the Volume and Balance capsules
· lifetime → Volume at range "All" · per plan and per workout → Volume, once attribution is stamped
(§8). L1 headlines only link into these.

**Grouping vocabulary.** A *session* is a set of `HistoryEntry` rows sharing an exact timestamp —
`SessionFinisher` fans one `date` to every entry it writes, so sessions are already reconstructible
without new storage. A *day* is `startOfDay`; a *week* is Sunday-anchored `StreakEngine.startOfWeek`,
matching the Calendar and the streak engine.

### Screen notes

- **L1 dashboard** — six cards, unchanged in structure. Headlines become effective-load aware; minis
  gain points and the clamped domain; Consistency de-stacks.
- **L2 Strength** — tiles (best effective e1RM · sessions · PRs); a top-3 dated line with PR trophy
  annotations; **when no lift yet has two sessions, a horizontal "latest session per lift" bar chart**
  so the screen is never line-blank; a four-type PR feed; and a searchable, muscle-filterable ranking
  with a Best/Recent/Volume sort toggle.
- **L2 Volume** — weekly tonnage bars (clamped, adaptive to per-day bars when fewer than three
  trained weeks exist), a **per-session tonnage chart**, the rep-range mix, an **intensity mix**
  (%1RM bins), an **equipment split**, and an average top-set RPE trend. Bars and rows push to the
  week.
- **L2 Muscles** — the donut with a tap-to-read centre, push/pull, and **weekly hard sets per muscle
  against a 10–20 sets/week reference band** — the dose metric that actually drives hypertrophy, where
  kilos alone mislead. Muscle attribution is weighted: 1.0 primary, 0.5 secondary.
- **L3 Muscle** — gains a `RangePicker` (it currently ignores the parent's window and hardcodes 12
  weeks), search over its exercises, and a hard-set tile.
- **L3 Week ★** — the week as a static analytic report: `CalendarStats.summary` tiles and a Sun→Sat
  seven-bar day chart. Deliberately *not* a preselected Calendar — the Calendar keeps its browse
  gestures; both render through the same `CalendarStats`, so no logic is duplicated.
- **L4 Training day ★** — the canonical per-day and per-session home, built from a `DayLogCard`
  extracted from the Calendar's day detail (one renderer, three hosts: Calendar, this, and
  `StatDetailSheet`). Splits into sections when a day holds more than one session.
- **L3 Exercise ✎** — the screen that showed nothing. Now: a tile row that works at n=1, a metric
  toggle (e1RM · Tonnage · Top weight), the full sparse ladder (set bars at n=1, a two-session
  comparison at n=2, a **dated** line at n≥3 — replacing the hidden session-index axis), a rep-PR
  ladder by 2.5 kg bin, and the expandable session log.
- **L2 Body** — relative strength finally works for calisthenics athletes now that effective load
  exists; adds a tonnage-to-bodyweight ratio and a full check-in history screen.

---

## 7. Filters

**Rule: no long unsearchable list, anywhere in the app.** Inline above the list, never a sheet.

`DesignSystem/SearchField` and `DesignSystem/FilterChip` are extracted from the Library's existing
private versions so Progress feels like the same app. `ProgressListFilter` (pure, tested) is
deliberately **lighter than `LibraryFilter`**: a name query plus OR-semantics primary-muscle chips —
the right tool for a ≤30-row list of exercises you've actually trained, where Library's AND-across
facets with a primary/secondary scope toggle would be ceremony. The chip row offers only muscles
present in the current ranking.

---

## 8. What isn't stored yet

Honest gaps, in the order they're worth closing:

1. **Session and plan attribution** — `ActiveSession` knows its `workoutId`, `name`, `planName` and
   `startedAt`, and all four are destroyed when the session is deleted on finish. Stamping them onto
   `HistoryEntry` as optionals unlocks "tonnage by plan / by workout" and session duration.
   **No backfill is possible**, so this ships early and accrues.
2. **Per-set RPE** — only the top set's RPE is kept. Would unlock true effort-adjusted intensity.
3. **`isTimed` persistence** — `RepScheme` parses it and then drops it before logging; until it is
   persisted, the verified hold exId list carries the seconds-in-reps hazard.
4. **Band tension** — unknowable, excluded by design.

---

## 9. Navigation

The Progress stack is value-routed end to end: one `ProgressRoute` enum plus `ExerciseRef`,
`WeekRef`, `DayRef` and `MuscleRef`, all registered once at the stack root via
`progressNavigationDestinations()` — the same shape as `planNavigationDestinations()`.

**Why it matters.** This stack used to mix destination-based `NavigationLink { View() }` with
value-based `NavigationLink(value:)`. A destination-based push is not represented in the stack's
path, so a value appended from a view one level deeper produced two disagreeing sources of truth: the
detail would begin to appear, the destination-based push would re-assert itself on top, and the
appended value would stay in the path forever. Seven taps left seven phantom entries to walk back
through. **One stack, one push mechanism** — the rule this document exists to keep.
