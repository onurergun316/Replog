# Replog Progress — Sparse-Data Specification

**Author:** lead product designer · **Status:** implementable · **Target:** `Replog/Features/Progress/*`, `Replog/Domain/ProgressAnalytics.swift`

---

## 0. The ruling, in one paragraph

All four defects are one architectural omission: **the Progress tab renders rates, shares and trends when a 3-session user only has counts and a cross-section.** A count is valid at n=1. A rate, a share, a delta and a trend are not. So: (a) every chart declares a minimum mark count and is *replaced* below it, never drawn degenerate — IBM Carbon's rule is that "empty states should replace the element that would ordinarily show" ([Carbon](https://v10.carbondesignsystem.com/patterns/empty-states-pattern/)); (b) every derived statistic is suppressed below denominator 2 and **swaps its metric**, never blanks; (c) the donut dies; (d) the range control is derived from the data, and renders nothing when it would offer one option.

We do **not** gate. WHOOP/Garmin/Oura gate because their metrics are literally undefined without a personal baseline; ours (sets, tonnage, e1RM, adherence-vs-plan) are absolute and defined on session one ([WHOOP calibration](https://support.whoop.com/hc/en-us/articles/360019622573-What-is-the-Recovery-calibration-period-)). We also do **not** ship ghost/skeleton/demo charts. Researcher D argued for muted preview charts; I'm overruling it — in a *health* app a grey fake trend line is read as the user's own body, and NN/g's three empty-state guidelines never call for placeholder data ([NN/g](https://www.nngroup.com/articles/empty-state-interface-design/)). We always have something real to show.

**One new pure type carries all of this:** `Domain/ChartDensity.swift`.

```swift
enum ChartDensity: Equatable {
    case none                 // 0 marks  → replace with a typed empty card
    case single               // 1 mark   → replace with a value + reference
    case sparse(Int)          // 2…4      → reduced chart, no axes, symbols on
    case full(Int)            // ≥5       → the chart as designed
    static func of(_ n: Int) -> ChartDensity
}
```
Every Progress card switches on it. This is one pure function with exhaustive tests and it kills all four bugs at once.

---

## 1. THE SPARSE-DATA LADDER

Screen width assumed 393pt (iPhone 17). Card inner width = 353pt; chart inner width = 325pt.

### 1A. Time bars — weekly tonnage, per-session tonnage, weekly adherence
*Volume is an accumulate-from-zero quantity at irregular intervals — both are line-chart contraindications, so it is bars at every n.* ([Datawrapper](https://www.datawrapper.de/academy/what-to-consider-when-creating-line-charts))

| n | Render |
|---|---|
| **0** | No chart. `ProgressEmptyCard` with an SF Symbol matching the chart type (`chart.bar.xaxis`), a heading that names the state ("No sets logged yet", never "No data"), one verb-first CTA. |
| **1** | One `BarMark`. Card chart height **96pt**. `.chartYScale(domain: 0...max*1.25)`, `.chartYAxis(.hidden)`, `.chartXAxis(.hidden)`. Value direct-labelled above the bar via `.annotation(position: .top)`. Caption below: `"1 session · 24 Jul"`. |
| **2** | Two bars, **96pt**, both direct-labelled, still no axes. |
| **3–4** | Bars, **140pt**. Y-axis appears (`AxisMarks(position: .leading)`, ≤3 marks). Direct labels drop. |
| **≥5** | Bars, **180pt** (200pt on L2). ≤4 gridlines — Apple's worked example uses "around four horizontal grid lines" ([WWDC22 110340](https://wwdcnotes.com/documentation/wwdc22-110340-design-an-effective-chart/)). Current period at full accent, prior at 0.45. |

**Hard rules:** bars always zero-based (Apple: fix the lower bound to 0 for bar charts, ibid.). Never draw an empty bucket window wider than the data — `trimmingLeadingEmptyWeeks` already does the left side; also clamp the x-domain to `firstActivity…today`.

### 1B. Time lines — e1RM per exercise, bodyweight
| n | Render |
|---|---|
| **0** | Typed empty card + CTA ("Log today's weight"). |
| **1** | **No chart at all.** Value at `.rounded(28, .black)` + date + one line of what unlocks next. Card collapses to ~96pt. *(Already correct in `BodyDetailView.weightChart`; port verbatim to `StrengthDetailView.topLiftChart` and to the L1 `bodyCard`/`strengthCard` minis.)* |
| **2** | `LineMark` + `PointMark`, `.interpolationMethod(.linear)`, `symbolSize(40)`, height **120pt**. X-domain = data span only. Y-domain = padded, min-span enforced (below). Caption: absolute change with a named date — `"−0.6 kg since 20 Jul"`. **Never** a percentage, an arrow badge, or the word "trend": convention is that two points aren't a trend line until a third confirms it ([Trend line](https://en.wikipedia.org/wiki/Trend_line_(technical_analysis))). |
| **3–4** | Same marks, height **160pt**, y-axis appears. Language allowed: "Recent", "Last 3 sessions". |
| **≥5** | Height **200pt**. `.monotone` permitted only from **n ≥ 8** (below that, smoothing invents curvature that isn't in the data). Symbols stay visible while n < 12 — Datawrapper: show symbols on all points when "data intervals are irregular or inconsistent" ([Datawrapper: patchy data](https://www.datawrapper.de/academy/patchy-data)). Word "trend" is now legal. Rolling 7-day mean from n ≥ 10. |

**Minimum y-span (new, non-negotiable):** never `.automatic` alone. Bodyweight: ≥ **4 kg / 10 lb**. e1RM: ≥ **max(10 kg, 15% of the max value)**. Two readings 0.3 kg apart on an auto-fitted axis render normal fluctuation as a cliff, and the perceptual exaggeration survives even explicit truncation cues ([Correll et al., *Truncating the Y-Axis*](https://arxiv.org/abs/1907.02035)). Lines stay non-zero-based; bars never do.

### 1C. Part-to-whole — muscle balance, rep-range mix, push/pull, load split
**No pie or donut at any n, in any card, ever.** (§5.)

| categories with data | Render |
|---|---|
| **0** | Hide the card entirely. A part-to-whole of nothing is not an empty state, it's noise. |
| **1** | No chart. One sentence: *"Everything you've logged so far is Push."* A 100% share is not information. |
| **2–3** | One 26pt stacked capsule + direct-label rows beneath (name · value · %). This is exactly today's `pushPull` / `repMixSection` / `loadSplitSection` pattern — **keep it, it's the good one.** 2pt surface gap between segments. |
| **≥4** | Ranked horizontal bars, one accent hue, no legend, **absolute counts**. (§5.) |

**Percentage gate:** shares render only when the denominator is **≥ 20 sets**. Below that, counts only. At 12 sets one set moves a share by 8 points, and "Chest 38%" from three sessions is false precision that swings wildly week to week.

### 1D. Ranked lists (exercises by e1RM, muscles by sets)
Valid from n=1 with no ladder. This is the form to lean on — it is a cross-section, not a time series.

### 1E. L1 mini charts (56–72pt, axis-free)
Apple: small static charts "don't require grid lines, labels, or interactivity" ([WWDC22 110342](https://wwdcnotes.com/documentation/wwdc22-110342-design-app-experiences-with-charts/)).
- **Bar mini:** renders at n ≥ 2.
- **Line mini:** renders at n ≥ 3.
- ~~**Below that: no mini chart.** `DashboardCard` renders `EmptyView()` for the chart and gains a second caption line instead. The card must shrink, not hold whitespace.~~
- `DesignSystem/Sparkline.swift`: requires **≥5** points.

> **Overruled by the owner, 24 Jul 2026 — every L1 card carries a preview.** Shipping the shrink
> rule made the dashboard look broken rather than restrained: Muscles rendered four bars while
> Volume, Consistency and Body beside it collapsed to a headline, and two cards of different sizes
> and shapes in the same grid read as a layout bug. `showsChart` is gone.
>
> The replacement rule keeps the honesty and drops the whitespace: **a card switches to a form its
> data supports rather than dropping to nothing.** Volume shows per-session bars until two weeks
> exist; Strength shows the ranked cross-section of lifts until one lift has three sessions;
> Consistency bands its bars on week position so a single week has width; Body plots its check-ins
> against a dashed starting-weight rule, which reads as one observation against a baseline instead
> of a dot adrift. Still no ghost data, no skeletons, no demo series — every mark is the athlete's.
> The 2-up rows are a `Grid`, so the pairs are the same height whatever the content does.

---

## 2. PER-SCREEN VERDICTS

### Volume — `VolumeDetailView`, L1 `volumeCard`
| | |
|---|---|
| **KEEP** | Weekly tonnage **bars** (right form, degrades to n=1). Per-session bars — Gravitus and FitNotes both treat the single workout as a first-class period ([FitNotes](http://www.fitnotesapp.com/progress_tracking/)). Rep-range capsule + label rows. Load-split capsule. Week-by-week list. |
| **REPLACE** | The bucket is currently always weekly. **Bucket must follow the resolved window** (§4): ≤5 weeks → per-session bars; >5 weeks–6 months → weekly; >6 months → monthly. Today a 4-day-old account gets one weekly bar; under this rule it gets 3 session bars and reads as a chart. Also: move **Per Session above Weekly** while `trained.count < 2`. |
| **REPLACE** | `summaryRow` is half-fixed (the `avg / session` fallback is correct). Complete it per §3 and add the invariant test. |
| **DROP** | Nothing. |

### Muscle Balance — `BalanceDetailView`, L1 `balanceCard`
| | |
|---|---|
| **DROP** | **The donut, both L1 and L2.** With 17 catalog muscles it is 2–3× over every published slice ceiling and it *cannot represent an untrained muscle at all* — which on a balance chart is the most important row on the screen. |
| **DROP** | The `FlowLayout` swatch legend. This is the thing that clips. |
| **REPLACE** | Ranked **horizontal bars**, top 6 + "Other", set counts not kilograms. Cleveland & McGill: position-along-a-common-scale beats angle by ~2× in accuracy ([FlowingData](https://flowingdata.com/2010/03/20/graphical-perception-learn-the-fundamentals-first/)). Full spec in §5. |
| **KEEP** | Push/Pull/Static capsule (2–3 segments, direct labels) — a legitimate part-to-whole. |
| **REPLACE** | Screen title: **"What You've Trained"** until 6 sessions, then "Muscle Balance". You cannot claim balance from three workouts. |

### Strength — `StrengthDetailView`, L1 `strengthCard`
| | |
|---|---|
| **KEEP** | The PR feed. It is the single densest-at-n=1 asset on the tab and the retention literature is unanimous that early achievement is the biggest lever ([Trophy](https://trophy.so/blog/mobile-app-engagement-strategies)). |
| **REPLACE** | `prEvents` deliberately excludes the first-ever session as "a baseline, not a PR" — technically honest, strategically wrong for a fresh install. **Emit `PREvent.kind = .baseline` for first-ever sessions** and render them as *"Baseline set · Squat 80 kg × 5 → 93 e1RM"* with a distinct icon and copy ("Beat one next session"). Still truthful, and it turns session 1 from a blank feed into eight wins. |
| **REPLACE** | `topLiftChart` plots up to 3 series regardless of density. Below n=2 per series it's a scatter of unconnected dots with a 3-item legend. Rule: **plot only series with ≥2 points**; if none qualify, replace the chart with the top-lift value card (ladder 1B, n=1). Legend renders only for ≥2 plotted series. |
| **REPLACE** | `.interpolationMethod(.monotone)` → linear below n=8. Enforce the e1RM min y-span. |
| **KEEP** | The "All Exercises" ranked list + filter chips — a cross-section, valid on day one. |

### Consistency — `ConsistencyDetailView`, L1 `consistencyCard`
| | |
|---|---|
| **KEEP** | The overlaid track+done bar (`yStart: 0` on both) is correct and the comment explaining why is right. Adherence is **the best metric on the tab for a new user** because its denominator comes from the *Plan*, not from history — it is fully meaningful at n=1. |
| **REPLACE** | Promote it. While `sessions < 6`, **Consistency becomes the L1 hero card**, above Strength: `"2 of 3 scheduled days · this week"` with the 4-week bar mini. Swap back to Strength once ≥6 sessions. This is progressive disclosure applied to the dashboard, and it matches Apple's own "goal-relative works on day one" model (Activity Rings). |
| **REPLACE** | Headline `"—"` when `scheduled == 0`. An em dash with no explanation is a dead end. Render `"No schedule yet"` + CTA to Plans. |
| **DROP** | Nothing. |

### Body — `BodyDetailView`, L1 `bodyCard`
| | |
|---|---|
| **KEEP** | The n=1 replacement card (value + "your starting point") — already correct, it is the model for the whole ladder. The relative-strength rows. The readiness stacked capsules. |
| **REPLACE** | L1 `bodyCard` still draws a `LineMark`+`PointMark` mini at n=1 → **one dot in a 56pt frame**. Apply 1E: no mini chart below 3 points. |
| **REPLACE** | `.chartYScale(domain: .automatic(includesZero: false))` → explicit padded domain with the 4 kg / 10 lb minimum span. |
| **ADD** | A reference line for the goal weight collected at onboarding: `RuleMark` + dashed stroke + `.annotation`. A lone value against a goal is Few's bullet graph — featured measure + comparative measure — which is *designed* to be informative for a single quantitative value ([Bullet graph](https://en.wikipedia.org/wiki/Bullet_graph)). This is what rescues n=1. |
| **DROP** | The `weeklyRateKg` tile below 3 check-ins (a rate from two points spanning 4 days extrapolates to nonsense). |

---

## 3. STAT TILES — the rules

**Row geometry.** 393 − 40 (page padding) − 24 (two 12pt gutters) = **329pt / 3 = 110pt per tile**. Researcher C argued 2-per-row max; I'm overruling for the common case and ruling by content instead:

> **3-across is legal only for tiles carrying `value + label`. Any tile carrying a delta line forces the row to 2-across.** A 110pt tile cannot hold label + value + signed delta at Dynamic-Type-safe SF Rounded sizes.

**Typography correction:** drop `.tabularNumbers()` from tile *values*. Tabular figures give every digit the width of a `0`, which makes a standalone display number look loose; reserve it for columns that must align — list rows, axis ticks. (Per the house dataviz standard.)

**The three laws.**

1. **Denominator ≥ 2.** No tile whose metric is an average, a rate, a percentage or a per-period figure renders when its denominator is 1. This is the discipline analytics products already use — GA4 suppresses below a minimum aggregation threshold *and says it did* ([GA4](https://support.google.com/analytics/answer/9383630)).
2. **Swap, never blank.** A suppressed tile is replaced by a metric with a *different denominator*, not by an em dash. Three tiles reading "—" tell a new athlete the screen is broken. Em dash is permitted only when the row would otherwise reflow (rare) and must carry a caption naming the threshold.
3. **No two tiles in a row may be computable to the same number for any input.** Domo's duplicate-metric rule ([Domo](https://www.domo.com/learn/article/top-10-dashboard-design-mistakes-and-what-to-do-about-them)) — two identical numbers don't waste space, they destroy trust in every other number on the screen. **This is a unit-testable invariant**, not a review note.

**Substitution ladders (implement exactly).**

*Volume:*
```
trainedWeeks ≥ 2 → [ Total kg | Avg / week + Δ vs prev week | Sets ]     (2-across if Δ shown)
trainedWeeks = 1, sessions ≥ 2 → [ Total kg | Avg / session | Sets ]
sessions = 1 → [ Total kg | Sets | Heaviest set ]
sessions = 0 → no row
```
*Body:*
```
checkIns ≥ 3 → [ Current | Δ vs last | kg / week ]
checkIns = 2 → [ Current | Δ vs last | Check-ins ]
checkIns = 1 → [ Current | Check-ins ] + caption "Log another and this becomes a trend."
```
*Consistency:* adherence % is legal at n=1 (denominator = the plan). Keep all three.

**Deltas.**
- Render only against a **named comparand**: `"▲ 8% vs last week"`, never a bare arrow.
- **n=2 → absolute delta only.** Percentages from n≥3.
- Direction colour uses `Color.up` / `Color.down`, never colour alone — pair with the arrow glyph and the sign.
- No delta exists on a first-week account. No previous period → no delta → no arrow.

---

## 4. THE RANGE CONTROL

The current `RangePicker` is already half-right: it's a `Menu` (correct — Apple's pop-up button is for "mutually exclusive options … when space is limited"), and `offered` derives options from `historySpanDays`. Four rulings complete it.

**Ruling 1 — collapse, don't disable.** Researchers split: Nielsen argues disabled controls aid discoverability ([uxtigers](https://www.uxtigers.com/post/inactive-buttons)); GOV.UK/NHS/NN-g argue against, and WCAG explicitly **exempts disabled controls from contrast requirements** ([W3C SC 1.4.3](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)). **Collapse wins**, on Nielsen's own carve-out for constrained mobile space: four greyed segments out of five is four pieces of dead chrome telling a 4-day-old user "you have nothing", every time they open the tab. The existing `offered` logic stands.

**Ruling 2 — one option means no control.**
```swift
if offered.count >= 2 { Menu { … } }
else { Text(rangeCaption) }   // "Since 20 Jul · 4 days"
```
A control whose every option resolves to the same records is a broken filter, and the caption carries the same information without the lie.

**Ruling 3 — the window drives the bucket.** Today the window changes and the weekly bucketing doesn't, so "4W" and "1Y" genuinely produce the same picture. Add to `Domain/ProgressRange.swift`:
```
resolvedSpan ≤ 35 days  → per-session marks
≤ 6 months              → weekly marks
> 6 months              → monthly marks
```
Target 6–14 marks on screen. Hevy ships window and aggregation as two orthogonal controls; Apple Health couples them implicitly (6M ⇒ weekly averages, Y ⇒ monthly). **Couple them** — a second control is not worth the complexity here.

**Ruling 4 — label "All time" with its span.** `"All time · since 20 Jul"`. The user then sees *why* the other options are equivalent instead of assuming the app is stuck.

**Custom range — replace the mechanism.** `CustomRangeSheet` ("show the last N days", a `NumericStepperField`) is dropped. Nobody thinks in "the last 47 days", and Replog **already owns a range picker**: the Calendar's long-press-drag multi-select feeding `RangeSummaryView`/`CalendarStats`. `"Custom range…"` pushes the Calendar in range-select mode and returns a `ClosedRange<Date>`; `RangeSelection` gains a `.dates(ClosedRange<Date>)` case. Two different date-range UIs in one tab is a worse bug than the one we're fixing. UXmatters' "presets + custom" pattern is right for analytics tools with arbitrary questions ([UXmatters](https://www.uxmatters.com/mt/archives/2011/08/date-filters-successful-calendar-design-patterns.php)); Pencil & Paper's mobile rule — use the native mechanism you already have, don't reinvent it — decides which custom mechanism.

**L1 keeps no range control.** Correct today. Preview charts get no axes, no gridlines, no interactivity.

---

## 5. MUSCLE BALANCE — the fix

**Is a donut right for 7 (really 17) muscle groups? No.** Not because the hole is bad — Skau & Kosara measured donuts as *equally accurate* to pies ([EuroVis 2016](https://eagereyes.org/publications/Skau-EuroVis-2016)) — but because the **task** is ranked comparison and the **colour budget** is blown. Datawrapper's hard ceiling: *"If you need more than seven colors in a chart, consider using another chart type or to group categories together"* ([Datawrapper](https://www.datawrapper.de/academy/what-to-consider-when-choosing-colors-for-data-visualization)). Six slices × six ramp steps × a wrapping `FlowLayout` key = the clipping you're seeing. **The legend is a symptom; the chart is the disease.** And `ProgressPalette.ramp` is a *sequential* monochrome scale being used categorically — a second, quieter bug that the bar chart also fixes, because a single-series chart needs no categorical hues at all.

**The replacement — ranked horizontal bars, in `BalanceDetailView` and the L1 `balanceCard`.**

| Property | Spec |
|---|---|
| Marks | `BarMark(x: .value("Sets", n), y: .value("Muscle", name))`, one accent hue for all bars over a `Color.track` capsule |
| Metric | **Absolute set count**, not kg, not % |
| Sort | Descending. Ordering creates the visual construct ([SWD](https://www.storytellingwithdata.com/blog/2012/10/my-penchant-for-horizontal-bar-graphs)) |
| Rows | Top 6 + one **"Other (n)"** row, tap to expand |
| Row anatomy | Label line: name leading `.rounded(13,.heavy)` · `"12 sets"` trailing `.rounded(12,.heavy)` tabular. Bar beneath: 8pt capsule, full 325pt width |
| Row pitch | 34pt; **44pt** where the row pushes `MuscleDetailView` (HIG touch target) |
| Legend | **None.** Carbon: "Your chart doesn't need a legend if it only presents one data category" ([Carbon](https://v10.carbondesignsystem.com/data-visualization/legends/)) |
| Zeros | **Show trained-zero rows.** Apple: with bars, "Zeros are visible without creating a distraction" ([WWDC22 110340](https://wwdcnotes.com/documentation/wwdc22-110340-design-an-effective-chart/)). A donut cannot draw an untrained muscle; on a balance chart that row is the point |
| Card height | 6 × 34 + Other + 56 header ≈ **294pt**, fits without scroll, and it *can grow* — a ring never can |

**Add a typical-range band, not a target.** `RuleMark`/`RectangleMark` at **10–20 sets/week**, labelled *"typical range"*, scaled down for beginners. This is what makes a single week meaningful — JEFIT's `12 / 12` reads perfectly after one workout where "avg per trained week" never will ([JEFIT Stimulus Volume Engine](https://www.jefit.com/wp/guide/the-stimulus-volume-engine/)). Sources disagree on the numbers (RP: MEV ~6–10, MAV 12–20, explicitly "starting points, not gospel"; Alpha Progression: 11–18; Nuckols: growth isn't proportional to hard sets at all), so **never** print "Target: 16". Label it "typical", and treat the band as needing its own sports-science sign-off before ship.

**Why sets, not kilograms:** tonnage makes a leg-press day look heroic and a strict-OHP day look like nothing. Every app that does muscle balance well counts sets (Hevy, Fitbod, Boostcamp, JEFIT, StrengthLog). Keep tonnage as the Volume headline — it's a good celebration number — and use hard sets for anything analytical.

**New pure function required:** `ProgressAnalytics.muscleSets(history:days:muscles:)` alongside the existing `muscleShares`, returning `[(muscle: Muscle, sets: Int)]` sorted descending.

---

## 6. TOP 10 RULES — ranked, each testable

| # | Rule | Test |
|---|---|---|
| **1** | **No two tiles in a row can produce the same number.** Averages/rates/percentages require denominator ≥ 2; below that the tile swaps metric, never blanks. | Property test over generated histories: for every screen, `Set(tileValues).count == tileValues.count`. |
| **2** | **Every chart declares a minimum mark count and is replaced below it** via `ChartDensity` — no chart is ever drawn degenerate. | `ChartDensity.of(n)` unit tests at n = 0,1,2,4,5; snapshot each Progress card at those n. |
| **3** | **A line mark is never drawn below 2 points; a line *chart* is never drawn below 2 points.** At n=1: value + date + reference, card ≤96pt. | Assert no `LineMark` is constructed when the series count < 2 (extract the series builders into pure funcs and test them). |
| **4** | **No donut, no pie, anywhere in Progress.** Part-to-whole ≤3 categories = stacked capsule; ≥4 = ranked horizontal bars. | Grep gate in CI: `SectorMark` must not appear under `Features/Progress`. |
| **5** | **No swatch legend on any Progress chart.** Direct labels or labelled rows only. | Grep gate: no `chartLegend(position:)` without an accompanying `.hidden`; no `FlowLayout` of `Circle().fill(ProgressPalette…)`. |
| **6** | **Bars are always zero-based; lines never are, and every line enforces a minimum y-span** (bodyweight ≥4 kg/10 lb; e1RM ≥ max(10 kg, 15%)). | `ChartScales.yDomain(for:minSpan:)` pure function + boundary tests. |
| **7** | **The range control renders only when it offers ≥2 distinguishable windows**, labels "All time" with its start date, and the window drives the bucket. | `ProgressRange.offered(span:)` and `.bucket(for:)` tests at spans 4d / 28d / 35d / 90d / 200d / 800d. |
| **8** | **Card height is a function of n.** No chart card taller than 100pt holds fewer than 3 marks; no mini chart below 3 marks (line) / 2 marks (bar). | Snapshot heights at n=1,2,3,5. |
| **9** | **Percentages require a denominator ≥ 20 sets; the word "trend" requires n ≥ 5; smoothing requires n ≥ 8.** | Copy-generation is a pure function (`ProgressCopy.caption(for:density:)`) — assert the forbidden words never appear below threshold. |
| **10** | **The first six sessions lead with plan-relative and achievement metrics, not time series:** Consistency is the L1 hero, first-session PRs render as "Baselines set". | `ProgressHomeView` card ordering is a pure `[ProgressRoute]` function of session count; test the ordering flips at 6. |

**Bonus (not in the ten, but do it):** add `REPLOG_SEED=1sess|2sess|empty` to `DebugSeed`. Every one of these four defects shipped because `DebugSeed` only ever produces a mature history. Apple's own instruction is verbatim: *"It's important to test your designs with real data early"* and *"design for a variety of scenarios in your data"* ([WWDC22 110340](https://wwdcnotes.com/documentation/wwdc22-110340-design-an-effective-chart/)). Sparse-data seeds are the cheapest permanent fix on this list.

---

## Appendix — files touched

| Path | Change |
|---|---|
| `Replog/Domain/ChartDensity.swift` | **new** — the ladder, pure |
| `Replog/Domain/ProgressRange.swift` | **new** — `offered(span:)`, `bucket(for:)`, `caption(for:)`, pure |
| `Replog/Domain/ProgressAnalytics.swift` | add `muscleSets(…)`; add `PREvent.kind (.record/.baseline)` |
| `Replog/Features/Progress/ProgressShared.swift` | `RangePicker`: caption fallback, dynamic "All time" label; drop `CustomRangeSheet` → Calendar range-select; `DashboardCard` accepts an optional chart |
| `BalanceDetailView.swift` | donut + `FlowLayout` legend → ranked horizontal set bars + typical-range band; conditional title |
| `VolumeDetailView.swift` | window-driven bucketing; per-session above weekly at low n; finish the tile ladder |
| `StrengthDetailView.swift` | series filter ≥2 points; n=1 value card; linear interpolation < n=8; baseline PRs |
| `BodyDetailView.swift` | min y-span; goal `RuleMark`; drop rate tile < 3 check-ins |
| `ConsistencyDetailView.swift` | `"—"` → "No schedule yet" + CTA |
| `ProgressHomeView.swift` | density-gated minis; card order flips at 6 sessions |
| `App/DebugSeed.swift` | `1sess` / `2sess` / `empty` seeds |