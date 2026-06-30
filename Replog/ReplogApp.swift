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
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.exerciseCatalog, .shared)
        }
        .modelContainer(container)
    }
}
