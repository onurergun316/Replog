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
