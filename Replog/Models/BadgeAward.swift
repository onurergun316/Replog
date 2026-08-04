//
//  BadgeAward.swift
//  Replog
//
//  A badge, earned, with the context it was earned in.
//
//  Like `HistoryEntry` and `CoachingLog` this is a flat record: it names the badge by its
//  stable string id rather than pointing at a definition, so the award outlives any change
//  to the catalogue, and it captures the plan and workout by name at the moment it was won,
//  so renaming or deleting a plan later cannot rewrite the athlete's history.
//
//  Awards are never revoked. A badge earned is earned.
//

import Foundation
import SwiftData

@Model
final class BadgeAward {
    var id: UUID = UUID()
    /// `Badge.id` in the static catalogue.
    var badgeId: String = ""
    var earnedAt: Date = Date()
    /// What was being trained when it landed, captured at the time.
    var planName: String?
    var workoutName: String?
    /// A short factual line about the moment, e.g. "10 workouts completed".
    var detail: String = ""

    init(badgeId: String, earnedAt: Date = Date(), planName: String? = nil,
         workoutName: String? = nil, detail: String = "") {
        self.badgeId = badgeId
        self.earnedAt = earnedAt
        self.planName = planName
        self.workoutName = workoutName
        self.detail = detail
    }

    /// The definition this award refers to, or nil if the id is no longer in the catalogue.
    var badge: Badge? { BadgeCatalog.badge(id: badgeId) }
}

extension ModelContext {

    /// Every badge earned, newest first.
    func badgeAwards() -> [BadgeAward] {
        let descriptor = FetchDescriptor<BadgeAward>(sortBy: [SortDescriptor(\.earnedAt, order: .reverse)])
        return (try? fetch(descriptor)) ?? []
    }

    /// The ids already earned, for the awarding pass to skip.
    func earnedBadgeIds() -> Set<String> {
        Set(badgeAwards().map(\.badgeId))
    }
}
