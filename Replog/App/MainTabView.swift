//
//  MainTabView.swift
//  Replog
//
//  The five-tab shell: Today · Plans · Library · Calendar · Profile.
//  (iPhone tab bars hold five — a sixth folds into a system "More" list — so Calendar
//  took Progress's slot; Progress lives behind a card at the top of Profile.)
//  Each tab owns a NavigationStack for drill-downs.
//

import SwiftUI

struct MainTabView: View {
    @State private var selection: Tab = .today

    enum Tab: Hashable { case today, plans, library, calendar, profile }

    init() {
        #if DEBUG
        if let tab = DebugSeed.initialTab { _selection = State(initialValue: tab) }
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "house") }.tag(Tab.today)
            PlansListView()
                .tabItem { Label("Plans", systemImage: "square.stack.3d.up") }.tag(Tab.plans)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }.tag(Tab.library)
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }.tag(Tab.calendar)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }.tag(Tab.profile)
        }
        .tint(.accent)
    }
}
