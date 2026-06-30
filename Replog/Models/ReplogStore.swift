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
        HistoryEntry.self, UserProfile.self, AppSettings.self
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

    /// History entries for one exercise, oldest first.
    func history(forExercise exId: String) -> [HistoryEntry] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.exId == exId },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? fetch(descriptor)) ?? []
    }
}
