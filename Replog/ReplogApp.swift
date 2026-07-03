//
//  ReplogApp.swift
//  Replog
//
//  App entry point. Wires the SwiftData container and the static catalog, then
//  shows onboarding or the main app via RootView.
//

import SwiftUI
import SwiftData

@main
struct ReplogApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let container: ModelContainer

    init() {
        let container = ReplogSchema.container()
        self.container = container
        // Create the singleton rows up front so no view ever mutates the context
        // during its body (which would thrash rendering / show a blank screen).
        let context = container.mainContext
        _ = context.userProfile()
        _ = context.appSettings()
        try? context.save()
        // Register the best-effort background report refresh (no-ops if not permitted).
        ReportScheduler.registerBackgroundTask(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.exerciseCatalog, .shared)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Publish any due weekly/monthly report whose boundary has passed, then
                // re-plan notifications from the fresh state.
                ReportScheduler.runOnActivation(context: container.mainContext)
                NotificationCoordinator.refresh(context: container.mainContext)
            case .background:
                ReportScheduler.scheduleBackgroundRefresh()
            default:
                break
            }
        }
    }
}
