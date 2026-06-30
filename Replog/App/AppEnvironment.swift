//
//  AppEnvironment.swift
//  Replog
//
//  Shared environment values (the static catalog) injected at the app root.
//

import SwiftUI

private struct ExerciseCatalogKey: EnvironmentKey {
    static let defaultValue: ExerciseCatalog = .shared
}

extension EnvironmentValues {
    var exerciseCatalog: ExerciseCatalog {
        get { self[ExerciseCatalogKey.self] }
        set { self[ExerciseCatalogKey.self] = newValue }
    }
}

/// Lightweight Identifiable wrapper so an exercise id can drive `.sheet(item:)`.
struct ExerciseRef: Identifiable, Hashable {
    let id: String
}
