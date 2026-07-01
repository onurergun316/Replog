//
//  LibraryView.swift
//  Replog
//
//  Browse the full 800+ catalog: search, quick equipment chips, a multi-facet
//  filter sheet, and rows that open the Guide-only exercise detail.
//

import SwiftUI

struct LibraryView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @State private var model = LibraryViewModel()
    @State private var showFilters = false

    /// Equipment types surfaced as quick chips above the list.
    private let quickEquipment: [Equipment] = [.barbell, .dumbbell, .cable, .machine, .bodyOnly]

    private var results: [Exercise] { model.results(in: catalog) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header
                list
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ExerciseRef.self) { ref in
                ExerciseDetailView(exId: ref.id, showProgress: false)
            }
            .sheet(isPresented: $showFilters) {
                LibraryFilterSheet(model: model, resultCount: results.count)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Library").font(.screenTitle).foregroundStyle(Color.textPrimary)
            searchField
            filterBar
            Text(results.count == 1 ? "1 exercise" : "\(results.count) exercises")
                .font(.rounded(12, .heavy)).textCase(.uppercase).tracking(1.1)
                .foregroundStyle(Color.text3)
        }
        .padding(.horizontal, 20)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.text3)
            TextField("Search exercises", text: $model.query)
                .font(.bodyText).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.text3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface2))
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            filtersButton
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickChip("All", isSelected: model.filter.equipment.isEmpty) {
                        model.filter.equipment = []
                    }
                    ForEach(quickEquipment) { eq in
                        quickChip(eq.displayName, isSelected: model.filter.equipment.contains(eq)) {
                            model.toggleEquipment(eq)
                        }
                    }
                    Color.clear.frame(width: 4)   // trailing breathing room before the fade
                }
            }
            // Constrain height so the (otherwise greedy) horizontal ScrollView + gradient
            // mask don't expand vertically and blow out the header spacing.
            .frame(height: 34)
            // Fade the chips out at the trailing edge instead of hard-cutting them.
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.9),
                                       .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            )
        }
    }

    private var filtersButton: some View {
        Button { showFilters = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .heavy))
                Text("Filters").font(.rounded(13, .heavy))
                if model.filter.activeCount > 0 {
                    Text("\(model.filter.activeCount)")
                        .font(.rounded(11, .black)).foregroundStyle(Color.accent)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Circle().fill(.white))
                }
            }
            .foregroundStyle(model.filter.isEmpty ? Color.text2 : .white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(model.filter.isEmpty ? Color.surface2 : Color.accent))
        }
        .buttonStyle(.plain)
    }

    private func quickChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.rounded(13, .heavy))
                .foregroundStyle(isSelected ? .white : Color.text2)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? Color.accent : Color.surface2))
        }
        .buttonStyle(.plain)
    }

    // MARK: List

    private var list: some View {
        List {
            ForEach(results) { ex in
                NavigationLink(value: ExerciseRef(id: ex.id)) {
                    LibraryRow(exercise: ex)
                }
                .listRowBackground(Color.bg)
                .listRowSeparatorTint(Color.border.opacity(0.6))
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 86 }  // inset past the thumbnail
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }
}

// MARK: - Row

private struct LibraryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 14) {
            ExerciseThumbnail(exercise: exercise, size: 58, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                Text(subtitle)
                    .font(.rounded(12, .semibold)).foregroundStyle(Color.text3).lineLimit(1)
                LevelBadge(level: exercise.level)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let equip = exercise.equipment?.displayName ?? "Bodyweight"
        let muscle = exercise.primaryMuscles.first?.displayName ?? ""
        return muscle.isEmpty ? equip : "\(equip) · \(muscle)"
    }
}
