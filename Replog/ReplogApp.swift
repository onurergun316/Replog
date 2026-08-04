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
        // Order matters. Attribution first: it stamps each history entry with the workout
        // and plan it came from, and the template repair below reads history *per plan*.
        // Run the other way round and every plan looks like it has no history at all.
        SessionAttributionBackfill.run(context: context)
        // One-time repair for plans logged before finishing wrote its numbers back.
        TemplateBackfill.run(context: context)
        // Merge any user-created exercises into the catalog so they resolve by exId everywhere.
        context.syncCustomExercises()
        // Recognise training that already happened. An athlete with two years of history
        // must not open this update to an empty trophy cabinet. Idempotent, so it is also
        // the safety net if a badge is ever missed at the end of a session.
        BadgeAwarding.award(context: context)
        try? context.save()
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
            default:
                break
            }
        }
    }
}
