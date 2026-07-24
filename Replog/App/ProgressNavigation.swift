//
//  ProgressNavigation.swift
//  Replog
//
//  Every destination the Progress tab can push, as one typed route registered once at
//  the stack root — the same shape as `planNavigationDestinations()`.
//
//  ONE STACK, ONE PUSH MECHANISM. The Progress stack used to mix destination-based
//  `NavigationLink { SomeView() }` with value-based `NavigationLink(value:)`. A
//  destination-based push isn't represented in the stack's path, so a value appended
//  from a view one level deeper left two disagreeing sources of truth: the detail
//  began to appear, the destination-based push re-asserted itself over the top, and
//  the appended value stayed in the path for good. Seven taps on an exercise row left
//  seven phantom entries to walk back through. Keep every Progress link value-based.
//

import SwiftUI

/// A screen inside the Progress onion. `ExerciseRef` stays its own type because it is
/// shared with Library and the workout editors, which push the same detail view.
enum ProgressRoute: Hashable {
    case calendar
    case strength
    case volume
    case balance
    case consistency
    case body
    case muscle(Muscle)
    /// A Sunday-anchored week start.
    case week(Date)
    /// A start-of-day.
    case day(Date)
    /// One of the Volume screen's headline numbers, opened up. `days` carries the window
    /// it was read in — a route can hold an `Int?` where it can't hold a `RangeSelection`,
    /// and a breakdown that silently changed window would contradict the tile you tapped.
    case volumeStat(VolumeStat, days: Int?)
}

extension View {
    /// Registers every Progress destination. Attach once, inside the stack's root view.
    func progressNavigationDestinations() -> some View {
        self
            .navigationDestination(for: ProgressRoute.self) { route in
                switch route {
                case .calendar:        CalendarView(embedded: true)
                case .strength:        StrengthDetailView()
                case .volume:          VolumeDetailView()
                case .balance:         BalanceDetailView()
                case .consistency:     ConsistencyDetailView()
                case .body:            BodyDetailView()
                case .muscle(let m):   MuscleDetailView(muscle: m)
                case .week(let start): WeekDetailView(weekStart: start)
                case .day(let day):    TrainingDayView(day: day)
                case .volumeStat(let stat, let days):
                    VolumeStatDetailView(stat: stat, days: days)
                }
            }
            .navigationDestination(for: ExerciseRef.self) { ref in
                ExerciseDetailView(exId: ref.id, showProgress: true)
            }
    }
}
