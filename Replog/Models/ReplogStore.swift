//
//  ReplogStore.swift
//  Replog
//
//  Central SwiftData schema, container factories, and fetch-or-create singletons
//  for UserProfile / AppSettings.
//

import Foundation
import SwiftData

enum ReplogSchema {
    /// All persisted model types.
    static let models: [any PersistentModel.Type] = [
        Plan.self, Workout.self, PlanItem.self, SetTemplate.self,
        ActiveSession.self, SessionExercise.self, LoggedSet.self,
        HistoryEntry.self, UserProfile.self, AppSettings.self,
        CoachingLog.self, BodyweightEntry.self
    ]

    /// The app's on-disk container.
    /// On a fresh device install `Library/Application Support` may not exist yet, which
    /// makes SwiftData fail to create its store ("Failed to create file; code = 2"). We
    /// create that directory first, then open the store; if the store itself is corrupt
    /// or schema-incompatible (e.g. left over from an older build), we wipe it once and
    /// retry, falling back to in-memory as a last resort so the app always launches.
    @MainActor
    static func container() -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        let storeURL = config.url

        // Ensure the store's parent directory exists.
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let c = try? ModelContainer(for: schema, configurations: config) { return c }

        // Genuine corruption / incompatible schema: remove the store files and retry once.
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        if let recovered = try? ModelContainer(for: schema, configurations: config) { return recovered }

        // Last resort so the UI still runs (data won't persist).
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// An ephemeral container for tests and SwiftUI previews.
    @MainActor
    static func inMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Force-try is acceptable here: an in-memory store cannot fail for schema reasons
        // that wouldn't also fail the on-disk store caught at app launch.
        return try! ModelContainer(for: Schema(models), configurations: config)
    }
}

// MARK: - Singleton fetch-or-create

extension ModelContext {
    /// Returns the single UserProfile, creating it on first access.
    func userProfile() -> UserProfile {
        if let existing = (try? fetch(FetchDescriptor<UserProfile>()))?.first {
            return existing
        }
        let profile = UserProfile()
        insert(profile)
        return profile
    }

    /// Returns the single AppSettings row, creating it on first access.
    func appSettings() -> AppSettings {
        if let existing = (try? fetch(FetchDescriptor<AppSettings>()))?.first {
            return existing
        }
        let settings = AppSettings()
        insert(settings)
        return settings
    }

    /// All plans in display order.
    func allPlans() -> [Plan] {
        let descriptor = FetchDescriptor<Plan>(sortBy: [SortDescriptor(\.order)])
        return (try? fetch(descriptor)) ?? []
    }

    /// Recomputes both streaks on `profile` from the current plan schedule + completed days.
    /// Call after finishing a workout or whenever the schedule changes.
    func recomputeStreaks(profile: UserProfile, today: Date = Date()) {
        let scheduled = StreakEngine.scheduledDays(in: allPlans())
        profile.streak = StreakEngine.workoutStreak(
            scheduledDays: scheduled, doneDates: profile.doneDates, today: today)
        profile.weekStreak = StreakEngine.weekStreak(
            scheduledDays: scheduled, doneDates: profile.doneDates, today: today)
    }

    /// History entries for one exercise, oldest first.
    func history(forExercise exId: String) -> [HistoryEntry] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.exId == exId },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? fetch(descriptor)) ?? []
    }

    // MARK: - Bodyweight

    /// All bodyweight check-ins, oldest first (matches `history(forExercise:)`).
    func bodyweightEntries() -> [BodyweightEntry] {
        let descriptor = FetchDescriptor<BodyweightEntry>(sortBy: [SortDescriptor(\.date)])
        return (try? fetch(descriptor)) ?? []
    }

    /// The most recent bodyweight check-in, if any.
    func latestBodyweight() -> BodyweightEntry? {
        var descriptor = FetchDescriptor<BodyweightEntry>(
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return ((try? fetch(descriptor)) ?? []).first
    }

    /// Records a bodyweight check-in. One entry per calendar day: logging again on the
    /// same day updates that day's entry instead of inserting a duplicate.
    @discardableResult
    func logBodyweight(_ weightKg: Double, date: Date = Date()) -> BodyweightEntry {
        if let sameDay = bodyweightEntries().last(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }) {
            sameDay.weightKg = weightKg
            sameDay.date = date
            return sameDay
        }
        let entry = BodyweightEntry(weightKg: weightKg, date: date)
        insert(entry)
        return entry
    }

    // MARK: - Coaching memory

    /// Records a coaching note into the durable memory and returns the inserted log.
    /// This is the single write path the trainer uses to "remember" something.
    @discardableResult
    func recordCoaching(
        _ kind: CoachingKind,
        summary: String,
        date: Date = Date(),
        exId: String? = nil,
        planId: UUID? = nil,
        payload: CoachingPayload = CoachingPayload(),
        bodyMarkdown: String? = nil
    ) -> CoachingLog {
        let log = CoachingLog(
            kind: kind, summary: summary, date: date,
            exId: exId, planId: planId, payload: payload,
            bodyMarkdown: bodyMarkdown
        )
        insert(log)
        return log
    }

    /// Coaching logs, newest first. Optionally filtered to one `kind` and capped to `limit`.
    func coachingLogs(kind: CoachingKind? = nil, limit: Int? = nil) -> [CoachingLog] {
        var descriptor = FetchDescriptor<CoachingLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        if let kind {
            let raw = kind.rawValue
            descriptor.predicate = #Predicate { $0.kindRaw == raw }
        }
        if let limit { descriptor.fetchLimit = limit }
        return (try? fetch(descriptor)) ?? []
    }

    /// The most recent coaching log of a given kind, if any.
    func latestCoachingLog(kind: CoachingKind) -> CoachingLog? {
        coachingLogs(kind: kind, limit: 1).first
    }

    /// Coaching logs concerning one exercise, newest first.
    func coachingLogs(forExercise exId: String) -> [CoachingLog] {
        let descriptor = FetchDescriptor<CoachingLog>(
            predicate: #Predicate { $0.exId == exId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? fetch(descriptor)) ?? []
    }
}
