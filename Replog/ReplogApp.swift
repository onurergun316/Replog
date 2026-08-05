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

    /// The StoreKit boundary and the access gate, created once and shared by every screen.
    @State private var subscriptions = SubscriptionStore()
    @State private var gate = PremiumGate()

    init() {
        let container = ReplogSchema.container()
        self.container = container
        // Create the singleton rows up front so no view ever mutates the context
        // during its body (which would thrash rendering / show a blank screen).
        let context = container.mainContext
        _ = context.userProfile()
        let settings = context.appSettings()
        // Stamp the one free day, once. This is the first moment the app has ever run, so it
        // is the only honest place to record it — and it must happen before any screen can ask
        // whether the athlete may train.
        if settings.freeDayDate == nil {
            settings.freeDayDate = AccessPolicy.freeDay(forFirstLaunchAt: Date())
        }
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
                .environment(subscriptions)
                .environment(gate)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Publish any due weekly/monthly report whose boundary has passed, then
                // re-plan notifications from the fresh state.
                ReportScheduler.runOnActivation(context: container.mainContext)
                NotificationCoordinator.refresh(context: container.mainContext)
                // Re-judge access against the current moment: a free day that ended overnight
                // has to end on screen too. Cancelling or switching a plan in Apple's sheet
                // changes renewal info WITHOUT producing a transaction, so `Transaction.updates`
                // never fires for it — coming back to the foreground is the only reliable
                // moment to notice.
                gate.revalidate()
                Task { await subscriptions.refresh() }
            default:
                break
            }
        }
    }
}
