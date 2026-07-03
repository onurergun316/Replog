# Replog — Test Plan (AI Personal Trainer cycle)

Running log of every test suite added per phase and what it asserts. The owner runs the
suite with coverage at the end of the cycle (see Phase 8). Per the no-simulator rule these
tests are written and compiled but not executed during the cycle.

Coverage target: **≥80% of the logic layer** (Domain, Models, Catalog, view models).

---

## Phase 1 — Program library foundation

**`ProgramCatalogTests`** (`ReplogTests/ProgramCatalogTests.swift`)
- `bundledLibraryLoadsAll62Programs` — the bundled `programs.json` decodes to exactly 62
  programs and the id index has 62 entries.
- `everyProgramIdIsUnique` — no duplicate ids across the library.
- `everyProgramHasNameAndAtLeastOneScheduleShape` — real invariant: every program has a
  non-empty name and prescribes work via `days`, `weeklyStructure`, or `monthlyWave`.
- `filteredQueriesResolve` — `programs(goal:)`, `programs(sport:)` return correct, non-empty
  sets; `program(id:)` misses return nil.
- `beginnerFullBodyFieldsAreCorrect` — spot-check #1: category, days/week, duration,
  audience sex/experience/age bounds, required equipment, and the first slot's
  pattern/sets/reps/rest/primary-muscle.
- `couchTo5kUsesWeeklyStructure` — spot-check #2: no `days`, 9 `weeklyStructure` weeks in
  ascending order, sport == running.
- `fiveThreeOneUsesMonthlyWaveSortedByWeek` — spot-check #3: `monthlyWave` flattened from
  the JSON object to 4 entries sorted week1…week4, last week is the deload.
- `decodesMinimalProgramWithOnlyIdAndName` — lenient: id+name only, everything else defaults.
- `programMissingIdIsDropped` — a program element without an id is dropped, others survive.
- `unknownPatternDecodesToOther` — unknown movement pattern → `.other(raw)`, optionals nil.
- `unknownMusclesAreDroppedFromSlot` — slot muscles map via `Muscle.lenient`, nonsense dropped.
- `unknownSexAndEmptyAgeRangeAreLenient` — unknown sex → `.other`, empty age range admits all.
- `bareTopLevelArrayIsAlsoAccepted` — loader tolerates a bare `[...]` as well as the wrapper.
- `everyKnownPatternRoundTripsThroughRawValue` — `MovementPattern(raw:)` ∘ `rawValue` == id.
- `patternRoundTripsThroughCodable` — encode/decode round-trips all known + an `.other`.
- `patternDecodingFoldsCaseAndWhitespace` — case/whitespace-insensitive parsing.
- `conditioningPatternsAreFlagged` — `isConditioningOrMobility` true for cardio/mobility only.
- `audienceAgeMembershipRespectsInclusiveBounds` — inclusive [min, max] membership.

---

## Phase 2 — Deterministic ProgramMatcher

**`ProgramMatcherTests`** (`ReplogTests/ProgramMatcherTests.swift`) — runs against the real
bundled library so every gate/score sees genuine data.
- `machineOnlyUserNeverGetsABandsRequiredProgram` — property: no bands-required program
  survives for a machine-only athlete.
- `bodyweightUserNeverGetsBarbellDumbbellCableMachineOrKettlebellPrograms` — property:
  bodyweight-only athlete never sees programs needing gear they lack.
- `disclaimerProgramsAreNeverInTheAutoPickSet` — across 3 contexts, every surviving
  disclaimer program is flagged non-auto-pickable and `topAutoPick` never returns one.
- `prerequisiteProgramsAreGatedForNoHistoryUsersButAllowedWithHistory` — run_10k_8wk
  (prereq "Can run 5K") is gated with no history, allowed once prerequisites are satisfied.
- `ageOutsideAudienceBandExcludesTheProgram` — teen_foundations_3d (age 14–18) dropped for
  a 50-year-old.
- `basketballSportUserGetsTheirSportProgramFirst` / `boxingSportUserGetsTheirSportProgramFirst`
  — the sport-specific program ranks #1 for that sport athlete.
- `customSportWithNoMatchFallsBackToGeneralAthleteProgram` — unmatched free-text sport →
  general-athletic (GPP) ranks first; no mismatched sport program leaks past the sport gate.
- `recognisedCustomSportMapsToItsProgram` — "bouldering" → climbing program first.
- `femaleFocusedProgramRanksHigherForWomenButStaysAvailableToMen` — sex-focus nudge boosts
  score for women while remaining auto-pickable for men (never exclusionary).
- `beginnerGetsBeginnerProgramsScoredForExperience` — beginner program yields an
  experience-fit reason for a beginner.
- `daysPerWeekFitBoostsAnExactMatch` — a 3-day program scores higher for a 3-day athlete
  than a 6-day one.
- `fatLossPersonaTopPickTargetsFatLossOrConditioning` — loseWeight persona's auto-pick has
  fat-loss/conditioning tokens.
- `everySurvivingProgramSatisfiesTheEquipmentGate` — invariant across 5 personas.
- `rankingIsDeterministicAndScoreSorted` — stable order + descending score.

---

## Phase 3 — Program-driven AI planner

**`PatternMappingTests`** (`ReplogTests/PatternMappingTests.swift`)
- `everyKnownPatternHasFacetsWithMuscleOrKeywordOrConditioning` — mapping is total over
  `MovementPattern`; each yields something to match on.
- `unknownPatternFallsBackToGeneralStrength` — `.other` → general compound strength facets.
- `everyKnownPatternYieldsCandidatesFromFullGymExceptSwim` — every pattern resolves to real
  candidates from a full gym; only `swim` (no catalog match) is empty.
- `squatCandidatesTrainLegMusclesAsPrimary` / `horizontalPushCandidatesTrainPushMuscles` —
  strength patterns require the right primary movers + category.
- `candidatesNeverUseUnavailableEquipment` — bodyweight athlete never offered gear they lack.
- `injuryAvoidedMuscleNeverAppearsAsPrimaryMover` — knee-avoided muscles excluded as primary.
- `slotMusclesRefineRanking` — authored slot muscles bias the ranking (glute hinge).
- `runCandidatesAreCardioMatchingKeywords` / `stretchStaticCandidatesAreStretchingCategory` /
  `plyometricCandidatesArePlyometricCategory` — conditioning/mobility patterns map to the
  right catalog category (and name keywords for cardio).

**`RepSchemeTests`** (`ReplogTests/RepSchemeTests.swift`)
- Counts/ranges (lower bound), per-side flagging, seconds & minutes→seconds (clamped),
  per-side time, unparseable prose→fallback, first-number extraction, rep clamping.
- RPE parsing from `"RPE 8"`/`"RPE 7-8"`(ceiling)/`"@8"`, nil when absent/out-of-range.
- `sets(for:)` builds the right count/reps/RPE/weight; default RPE; clamps set count ≥1.

**`ProgramPlanBuilderTests`** (`ReplogTests/ProgramPlanBuilderTests.swift`, @MainActor)
- `deterministicPlanCarriesProgramIdRestAndParsedReps` — real program → plan with programId,
  progression, per-item rest, parsed reps, and a real leg-compound for a squat slot.
- `timeBasedSlotEncodesSecondsInReps` — a `"30-60s"` core slot → 30s target.
- `slotWithNoCandidatesIsSkipped` — a swim slot is dropped; the squat slot resolves.
- `validModelPickIsUsedInvalidFallsBackToTopCandidate` — pick validation against the slot's
  candidate set (right pattern/equipment); invalid → top candidate.
- `resolveDayDoesNotRepeatAnExerciseAcrossSlots` — dedup across identical slots.
- `reportSurfacesProgramScienceAndCautions` / `reportFoldsInjuriesIntoSafetyNotes`.
- `insertingAProgramPlanPersistsMetadataAndRest` — end-to-end through `PlanFactory` +
  in-memory container: programId, progression, and PlanItem.restSeconds persist and re-fetch.

**`AIPlanServiceTests`** (`ReplogTests/AIPlanServiceTests.swift`, @MainActor) — rewritten for
the program-driven flow.
- Framing prompt embeds the profile + real candidate program list; embeds logged history and
  differs from empty; stays under the token budget with margin worst-case; trims candidates
  but never below the floor under pressure.
- Slot-selection prompt lists slots + real candidates; `alignPicks` maps flat model picks
  onto slots; instructions are science-grounded.
- Fallback is program-driven (programId + progression ride along) and produces a valid
  plan+report; the fallback never picks a disclaimer program.

**`PlannerEvalTests`** — updated `richHistoryProducesADifferentInBudgetPromptThanEmpty` to the
new program-driven framing prompt signature (rest unchanged, exercising `PlanGenerator`).

---

## Phase 4 — CoachEngine (explainable insights)

**`CoachEngineTests`** (`ReplogTests/CoachEngineTests.swift`, @MainActor) — fixture personas
over the pure engine, asserting the right insight kinds, priorities, and reason strings.
- `progressingSessionYieldsDebriefAndPRNoStall` — a progressing session → sessionDebrief
  (carrying the next-session recommendation reason + "up X% volume") + a high-priority PR
  milestone; never a stall alert.
- `stallingSessionYieldsStallAlertWithDeloadReason` — four flat sessions → a high-priority
  stall alert whose body explains "stuck … deload to <computed>".
- `stallAlertPrefersProgramDeloadRuleWhenPresent` — the program's own deload rule is quoted
  when program-driven.
- `scheduledUndoneWorkoutWithStreakYieldsHighAdherenceAlert` — streak-at-risk → high
  adherence insight ("N-workout streak … on the line"); suppressed once today is done.
- `favorableBodyweightTrendReadsAsRightDirection` — a downward trend for a fat-loss goal
  reads as the right direction; `checkInDueYieldsAPrompt`.
- `stallOutranksBodyweightTrendForTheTodayCard` — priority ordering for the single Today card.
- `freshUserGetsOnlyWelcome` — a brand-new user gets exactly one welcome insight.
- `freshUserWithOneSessionGetsDebriefNeverStall` — no-spam property: one session → a debrief,
  never a stall alert, and welcome is superseded.
- `streakMilestoneFiresOnRoundNumbers` — milestone on 7, not on 8.

(The MainActor surfacing — `CoachContextBuilder`, `CoachVoice`, the Today card, the debrief
sheet, and the Profile "Coach Insights" section — is wired but, like the other AI seams, its
live model path is verified on device, not unit-tested. The pure engine it feeds is covered
above.) `readinessPatternSurfacesAReadinessInsight` added in Phase 5.

---

## Phase 5 — Readiness check-in + session modulation

**`ReadinessModulatorTests`** (`ReplogTests/ReadinessModulatorTests.swift`, pure)
- Modulation table: fresh/light → normal; load 2–3 → capIntensity; load ≥4 → trimLastSet;
  only trim reduces volume.
- Reason strings: empty for normal; names the flagged dimensions ("poor sleep", "high
  soreness") and leads with the poorest signal; correct verb per modulation.
- Pattern detection: three low-sleep days in the window → `.lowSleep(3)`; two days is not
  yet a pattern; stale days outside the 7-day window don't count; the dominant pattern wins.

**`ReadinessSessionTests`** (`ReplogTests/ReadinessSessionTests.swift`, @MainActor, in-memory)
- `skipPathLeavesTheSessionUntouched` — no check-in → 3 sets/exercise, empty note.
- `normalReadinessDoesNotTrimAndLeavesNoNote` — `.fresh` → unchanged, no note.
- `moderateReadinessCapsIntensityWithoutTrimming` — load 2 → volume kept, "Capped
  intensity" note.
- `highFatigueTrimsTheLastSetOfEachExerciseAndNotes` — load 6 → each exercise 3→2 sets,
  trimmed sets actually deleted from the store, "Trimmed a set" note.
- `loggingAReadinessCheckInPersistsOnePerDay` — same-day re-log overwrites, latest wins.

---

## Phase 6 — Weekly/monthly narrative reports

**`MonthlyReportTests`** (`ReplogTests/MonthlyReportTests.swift`, @MainActor)
- `statMathIsExact` — total sets, total volume (Σ w×r), days trained; markdown has the
  headline + "Recommended adjustment" section.
- `adherencePercentIsWholePercent` — the pure `MonthStats.adherencePct` (6/8 → 75; none
  scheduled → nil).
- `adherenceSurvivesCompositionCoherently` — adherence stays within 0–100 and
  scheduledDone ≤ scheduledCount through a real composition.
- `topMoversRanksBiggestPositiveClimb` — e1RM movers rank by biggest positive first→last
  climb; single-entry and decreasing lifts are excluded.
- `composeSurfacesNewRecordsAgainstPriorHistory` — a new best vs pre-month history is a
  record (reusing the weekly PR detector).
- `startOfMonthNormalisesToTheFirst`, `lastCompletedMonthIsThePriorMonth`,
  `lastCompletedMonthRollsOverTheYear` — month boundary logic incl. Jan→Dec year rollover.
- `publishIfDueIsIdempotentPerMonth` — second publish returns nil; exactly one monthly log.
- `idleMonthPublishesNoReport` — an empty month publishes nothing.

The existing **`WeeklyReportTests`** already cover the weekly composer (stat math, PR
detection, dedup); Phase 6 wires its `publishIfDue` (previously uncalled) plus the new
monthly one into `ReportScheduler.runOnActivation`, fired from the app's `scenePhase == .active`.
The `BGTaskScheduler` app-refresh path is best-effort and untested (it requires the Info.plist
`BGTaskSchedulerPermittedIdentifiers` entry + Background Modes to run at all, and iOS decides
if/when) — documented in `ReportScheduler`.
