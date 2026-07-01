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
    @State private var addRef: ExerciseRef?

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
            .sheet(item: $addRef) { ref in
                AddToWorkoutSheet(exId: ref.id)
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
        HStack {
            filtersButton
            Spacer()
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
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { addRef = ExerciseRef(id: ex.id) } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .tint(.accent)
                }
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
