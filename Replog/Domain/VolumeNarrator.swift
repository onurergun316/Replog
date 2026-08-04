//
//  VolumeNarrator.swift
//  Replog
//
//  Turning a tonnage into a picture.
//
//  "You moved 6,074 kg" is true and forgettable. "That is three Smart cars" is the same
//  fact with a handle on it. This picks the reference that best fits a total and phrases it.
//
//  Three rules make the output feel written rather than generated:
//
//  1. **A count you can see.** Two to twelve of something is imaginable; 0.4 of a bus and
//     380 washing machines are not. Candidates are scored on how close their count lands to
//     that band, so the reference grows with the athlete: a first session is beer kegs, a
//     year is locomotives.
//  2. **Never the same twice in a row.** A `seed` (the session, the week, the day) rotates
//     between equally good candidates, so a weekly summary doesn't say "buses" every week.
//     The same seed always gives the same answer, which is what makes it testable.
//  3. **Honest about its sources.** Animal strength figures are largely folklore, so an
//     unverified one is hedged ("reportedly") rather than stated as fact.
//

import Foundation

/// A chosen comparison, ready to drop into a sentence.
struct VolumeComparison: Equatable, Sendable {
    /// The reference that was picked.
    var id: String
    /// How many of it, rounded to something sayable.
    var count: Int
    /// "3 city buses" — count and noun already agreed.
    var phrase: String
    /// A whole sentence, e.g. "That is about 3 city buses."
    var sentence: String
}

enum VolumeNarrator {

    /// The band a count should ideally land in. Below it the comparison is bigger than the
    /// athlete's total and reads as a put-down; far above it the number stops meaning
    /// anything.
    static let idealRange: ClosedRange<Double> = 2...12
    /// Hard limits outside which a candidate is not considered at all. The floor is exactly
    /// one: "that is a city bus" is a fine thing to say, "that is 0.4 of a city bus" is not.
    static let acceptableRange: ClosedRange<Double> = 1...60

    // MARK: - Picking

    /// The best comparison for `kg` among `candidates`, or nil when nothing fits.
    ///
    /// `seed` breaks ties deterministically. Candidates within a whisker of the best score
    /// are treated as equally good and rotated between, so repeated summaries vary.
    static func comparison(forKg kg: Double, among candidates: [WeightComparison],
                           seed: Int = 0) -> VolumeComparison? {
        guard kg > 0 else { return nil }
        let scored = candidates.compactMap { candidate -> (item: WeightComparison, count: Double, score: Double)? in
            guard candidate.kg > 0 else { return nil }
            let count = kg / candidate.kg
            guard acceptableRange.contains(count) else { return nil }
            return (candidate, count, score(for: count))
        }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }

        // Everything close to the best is a fair choice; rotate so copy doesn't repeat.
        let contenders = scored.filter { $0.score >= best.score - 0.15 }
            .sorted { $0.item.id < $1.item.id }      // stable regardless of file order
        let chosen = contenders[abs(seed) % contenders.count]
        return describe(chosen.item, count: chosen.count)
    }

    /// How good a count is: 1 at the middle of the ideal band, falling off outside it.
    /// Scored on a log scale because 24 is as far from 12 as 6 is from 12, perceptually.
    static func score(for count: Double) -> Double {
        guard count > 0 else { return 0 }
        let low = idealRange.lowerBound, high = idealRange.upperBound
        if count >= low && count <= high { return 1 }
        let distance = count < low ? log(low / count) : log(count / high)
        return max(0, 1 - distance)
    }

    /// Rounds a raw count to something a person would actually say and builds the copy.
    private static func describe(_ item: WeightComparison, count: Double) -> VolumeComparison {
        let rounded = max(1, Int(count.rounded()))
        let phrase = item.phrase(count: rounded)
        // "about" only when the rounding actually moved the number appreciably.
        let approximate = abs(count - Double(rounded)) > 0.1
        let lead = approximate ? "That is about " : "That is "
        return VolumeComparison(id: item.id, count: rounded, phrase: phrase,
                                sentence: lead + phrase + ".")
    }

    // MARK: - Tonnage

    /// A comparison for a lifted total, drawn from objects and animals together.
    static func tonnage(kg: Double, catalog: ComparisonCatalog, seed: Int = 0) -> VolumeComparison? {
        comparison(forKg: kg, among: catalog.masses, seed: seed)
    }

    /// A sentence for a lifted total, or nil when nothing fits. The phrasing is a
    /// lifting verb rather than "that is", so it reads as a compliment.
    static func tonnageSentence(kg: Double, catalog: ComparisonCatalog, seed: Int = 0) -> String? {
        guard let match = tonnage(kg: kg, catalog: catalog, seed: seed) else { return nil }
        return "That is \(match.phrase) lifted off the floor."
    }

    // MARK: - Strength

    /// A comparison against animal force for how the athlete's own volume was produced.
    static func strength(kg: Double, force: Force, catalog: ComparisonCatalog,
                         seed: Int = 0) -> VolumeComparison? {
        comparison(forKg: kg, among: catalog.strength(for: force), seed: seed)
    }

    /// A sentence comparing pressed or pulled volume to animal strength.
    ///
    /// Hedged by how well sourced the figure is: most animal strength numbers are repeated
    /// folklore, and the app says "roughly" or "reportedly" rather than inventing certainty.
    /// The nouns already carry their own claim ("gorillas' lifting strength", "oxen's sled
    /// loads"), so a dragged sled is never described as something that was lifted.
    static func strengthSentence(kg: Double, force: Force, catalog: ComparisonCatalog,
                                 seed: Int = 0) -> String? {
        guard let match = strength(kg: kg, force: force, catalog: catalog, seed: seed),
              let item = catalog.strength.first(where: { $0.id == match.id }) else { return nil }
        let verb = force == .push ? "pressed" : "pulled"
        return "You \(verb) the equivalent of \(item.confidence.hedge)\(match.phrase)."
    }

    // MARK: - Seeds

    /// A stable seed from a date, so the same day always narrates the same way while
    /// different days rotate. Days since a fixed epoch, which is monotonic and cheap.
    static func seed(for date: Date, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0),
                                           to: date).day ?? 0
        return abs(days)
    }
}
