//
//  PlanNavigation.swift
//  Replog
//
//  Shared navigation destinations for the Plan -> Workout drill-down, so any tab's
//  stack can push them.
//

import SwiftUI

extension View {
    func planNavigationDestinations() -> some View {
        self
            .navigationDestination(for: Plan.self) { PlanDetailView(plan: $0) }
            .navigationDestination(for: Workout.self) { WorkoutEditorView(workout: $0) }
    }
}
