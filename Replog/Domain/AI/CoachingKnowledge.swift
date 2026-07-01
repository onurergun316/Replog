//
//  CoachingKnowledge.swift
//  Replog
//
//  A curated, evidence-based "coaching cheat-sheet" injected into the model's system prompt
//  so its programming decisions are grounded in established exercise science — not generic
//  guesses. This is the practical, on-device way to "feed science" into Apple Intelligence:
//  the model has a small context window, so we distill principles here rather than dumping
//  raw papers. Edit/extend this text to refine the model's scientific behavior.
//
//  (If you later want true paper-grounding, this is where a retrieval step would inject the
//  most relevant snippets per request — see notes in the PR/README.)
//

import Foundation

enum CoachingKnowledge {

    /// Distilled, evidence-based resistance-training principles. Kept compact to fit the
    /// on-device model's context window.
    static let principles = """
    EVIDENCE-BASED TRAINING PRINCIPLES (apply these):
    • Volume: ~10-20 hard sets per muscle per week drives hypertrophy; beginners progress on the \
    lower end, advanced trainees nearer the top. More is not always better.
    • Frequency: training each muscle ~2x/week beats 1x for the same weekly volume (protein \
    synthesis stays elevated ~48h).
    • Intensity & reps: 6-12 reps is the hypertrophy core, but 5-30 reps near failure all build \
    muscle; 3-6 reps bias strength; 12-20 bias muscular endurance / metabolic stress.
    • Proximity to failure: most working sets at RPE 7-9 (1-3 reps in reserve). True failure \
    sparingly, mostly on isolation/machine work.
    • Progressive overload: add load, reps, or sets over time. Small, consistent increments win.
    • Exercise order: compound, multi-joint lifts first when fresh; isolation and machines later.
    • Split logic: pair synergists (e.g. chest/shoulders/triceps = push) or use upper/lower or \
    full-body by available days; balance push/pull and knee/hip patterns to avoid imbalance.
    • Selection: cover each target muscle's main function; mix a heavy compound with 1-2 \
    isolation/stretch-position movements; respect equipment available.
    • Recovery: ~48h before training a muscle hard again; sleep and protein (~1.6-2.2 g/kg/day) \
    underpin adaptation.
    • Injuries: never load a flagged joint/region as a primary mover; choose pain-free, \
    joint-friendly variations and brace/warm up thoroughly.
    """

    /// Prepends the principles to a role/system instruction.
    static func grounded(_ instruction: String) -> String {
        instruction + "\n\n" + principles
    }
}
