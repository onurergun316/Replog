//
//  ReportScheduler.swift
//  Replog
//
//  Triggers the weekly & monthly narrative reports honestly. The reliable path is
//  `runOnActivation` — called when the app becomes active, it publishes any due report whose
//  period boundary has passed since the last one of that kind (idempotent per period).
//
//  As a best-effort supplement it also registers a `BGTaskScheduler` app-refresh task that does
//  the same opportunistically. iOS decides whether and when to run background refresh — it may
//  never fire (low battery, Low Power Mode, the user force-quit, or the identifier isn't
//  declared in Info.plist's `BGTaskSchedulerPermittedIdentifiers` + Background Modes). The
//  on-activation path does not depend on it.
//

import Foundation
import SwiftData
import BackgroundTasks

@MainActor
enum ReportScheduler {

    /// The app-refresh task identifier. Must also be listed in Info.plist
    /// (`BGTaskSchedulerPermittedIdentifiers`) with the Background fetch capability enabled
    /// for iOS to ever schedule it; otherwise registration/scheduling simply no-op.
    static let refreshTaskID = "test.Replog.reportRefresh"

    /// Publishes any due weekly and monthly reports. Safe to call on every activation.
    @discardableResult
    static func runOnActivation(context: ModelContext, now: Date = Date()) -> (weekly: CoachingLog?, monthly: CoachingLog?) {
        let weekly = WeeklyReportComposer.publishIfDue(context: context, now: now)
        let monthly = MonthlyReportComposer.publishIfDue(context: context, now: now)
        return (weekly, monthly)
    }

    // MARK: - Background refresh (best-effort)

    /// Registers the background-refresh handler. Call once at launch. Returns whether the
    /// system accepted the registration (false when the identifier isn't permitted, e.g. the
    /// Info.plist entry is absent — the app still works via `runOnActivation`).
    @discardableResult
    static func registerBackgroundTask(container: ModelContainer) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            MainActor.assumeIsolated {
                runOnActivation(context: container.mainContext)
                scheduleBackgroundRefresh()          // chain the next opportunity
                task.setTaskCompleted(success: true)
            }
        }
    }

    /// Requests the next opportunistic background refresh (~24h out). Best-effort: iOS may
    /// coalesce, defer, or never run it. Silently no-ops when background tasks aren't permitted.
    static func scheduleBackgroundRefresh(now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = now.addingTimeInterval(24 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
