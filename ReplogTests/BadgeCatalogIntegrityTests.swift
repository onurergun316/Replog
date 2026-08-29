//
//  BadgeCatalogIntegrityTests.swift
//  ReplogTests
//
//  The badge board is 70-odd static definitions, and everything about a medal — its
//  colours, whether its unlock is spoiled while locked, what its family is called — is
//  read off them at render time. A definition with a palette nobody defined, or a family
//  with no heading, is a silently wrong medal rather than a crash, so it has to be caught
//  here.
//

import Testing
import Foundation
@testable import Replog

struct BadgeCatalogIntegrityTests {

    // MARK: - Families

    @Test func everyFamilyHasAnIdentityAndCopy() {
        for family in BadgeFamily.allCases {
            #expect(family.id == family.rawValue)
            #expect(!family.title.isEmpty)
            #expect(!family.blurb.isEmpty)
        }
        #expect(BadgeFamily.foundations.title == "Foundations")
        #expect(BadgeFamily.curiosities.title == "Curiosities")
    }

    @Test func onlyCuriositiesKeepTheirUnlockHidden() {
        for family in BadgeFamily.allCases {
            #expect(family.revealsCriterionWhenLocked == (family != .curiosities))
        }
    }

    @Test func aLockedBadgeRevealsItsHintUnlessItIsACuriosity() throws {
        let curiosity = try #require(BadgeCatalog.badges(in: .curiosities).first)
        let foundation = try #require(BadgeCatalog.badges(in: .foundations).first)

        #expect(!curiosity.revealsHintWhenLocked)
        #expect(foundation.revealsHintWhenLocked)
    }

    // MARK: - The catalogue itself

    @Test func everyBadgeIsFullyDefined() {
        for badge in BadgeCatalog.all {
            #expect(!badge.id.isEmpty)
            #expect(!badge.name.isEmpty)
            #expect(!badge.hint.isEmpty, "\(badge.id) has no hint")
            #expect(!badge.meaning.isEmpty, "\(badge.id) has no meaning")
        }
    }

    @Test func badgeIdsAreUniqueBecauseAwardsPersistThem() {
        // An award stores the id; two badges sharing one would be indistinguishable forever.
        #expect(Set(BadgeCatalog.all.map(\.id)).count == BadgeCatalog.all.count)
    }

    @Test func lookupResolvesAKnownIdAndRefusesAnUnknownOne() throws {
        let first = try #require(BadgeCatalog.all.first)
        #expect(BadgeCatalog.badge(id: first.id)?.name == first.name)
        #expect(BadgeCatalog.badge(id: "no-such-badge") == nil)
    }

    @Test func everyFamilyHasBadgesAndTheyAllBelongToIt() {
        for family in BadgeFamily.allCases {
            let badges = BadgeCatalog.badges(in: family)
            #expect(!badges.isEmpty, "\(family.rawValue) is empty")
            #expect(badges.allSatisfy { $0.family == family })
        }
        #expect(BadgeFamily.allCases.reduce(0) { $0 + BadgeCatalog.badges(in: $1).count }
                == BadgeCatalog.all.count)
    }

    // MARK: - Palettes

    @Test func everyBadgeNamesAPaletteThatExists() {
        // A missing palette falls back to bronze silently, so this is the only place a
        // typo in a definition can be caught at all.
        for badge in BadgeCatalog.all {
            #expect(MedalPalettes.ids.contains(badge.palette),
                    "\(badge.id) names palette '\(badge.palette)', which is not defined")
        }
    }

    @Test func aKnownPaletteResolvesToItsOwnThreeColours() {
        let triple = MedalPalettes.triple("goldOlympic")
        #expect(triple.body == "#D6AF36")
        #expect(triple.accent == "#824A02")
        #expect(triple.detail == "#F2D98A")
    }

    @Test func anUnknownPaletteFallsBackRatherThanDisappearing() {
        #expect(MedalPalettes.triple("no-such-palette") == MedalPalettes.fallback)
    }

    @Test func everyPaletteIsThreeHexColours() {
        for (id, triple) in MedalPalettes.hex {
            for hex in [triple.body, triple.accent, triple.detail] {
                #expect(hex.hasPrefix("#"), "\(id) has a non-hex component")
                #expect(hex.count == 7, "\(id) has a malformed hex \(hex)")
            }
        }
        #expect(MedalPalettes.ids.count == MedalPalettes.hex.count)
    }
}
