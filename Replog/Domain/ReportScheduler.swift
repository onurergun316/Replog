//
//  ReportScheduler.swift
//  Replog
//
//  Triggers the weekly & monthly narrative reports honestly. The reliable path is
//  `runOnActivation` — called when the app becomes active, it publishes any due report whose
//  period boundary has passed since the last one of that kind (idempotent per period).
//
//  There is no background-refresh path: with no backend and reports read in-app, opening the
//  app (which always runs `runOnActivation`) is the only moment a report needs to appear, so a
//  `BGTaskScheduler` task would add a Background Mode / Info.plist surface for no user-visible
//  gain — and iOS may never run it anyway.
//

import Foundation
import SwiftData

@MainActor
enum ReportScheduler {

    /// Publishes any due weekly and monthly reports. Safe to call on every activation.
    @discardableResult
    static func runOnActivation(context: ModelContext, now: Date = Date()) -> (weekly: CoachingLog?, monthly: CoachingLog?) {
        let weekly = WeeklyReportComposer.publishIfDue(context: context, now: now)
        let monthly = MonthlyReportComposer.publishIfDue(context: context, now: now)
        return (weekly, monthly)
    }
}
