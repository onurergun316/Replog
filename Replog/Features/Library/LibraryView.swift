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
    @State private var selectionMode = false
    @State private var selected: Set<String> = []
    @State private var showMultiAdd = false

    private var results: [Exercise] { model.results(in: catalog) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header
                list
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { multiAddBar }
            .navigationDestination(for: ExerciseRef.self) { ref in
                ExerciseDetailView(exId: ref.id, showProgress: false)
            }
            .sheet(isPresented: $showFilters) {
                LibraryFilterSheet(model: model, resultCount: results.count)
            }
            .sheet(item: $addRef) { ref in
                AddToWorkoutSheet(exIds: [ref.id])
            }
            .sheet(isPresented: $showMultiAdd, onDismiss: {
                withAnimation(.snappy) { selectionMode = false; selected.removeAll() }
            }) {
                AddToWorkoutSheet(exIds: Array(selected))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library").font(.screenTitle).foregroundStyle(Color.textPrimary)
                Spacer()
                Button {
                    withAnimation(.snappy) {
                        selectionMode.toggle()
                        if !selectionMode { selected.removeAll() }
                    }
                } label: {
                    Text(selectionMode ? "Cancel" : "Select")
                        .font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
                }
                .buttonStyle(.plain)
            }
            searchField
            filterBar
            Text(results.count == 1 ? "1 exercise" : "\(results.count) exercises")
                .font(.rounded(12, .heavy)).textCase(.uppercase).tracking(1.1)
                .foregroundStyle(Color.text3)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var multiAddBar: some View {
        if selectionMode && !selected.isEmpty {
            Button { showMultiAdd = true } label: {
                Text("Add \(selected.count) to workout")
                    .font(.rounded(16, .heavy)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accent))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
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
                row(ex)
                    .listRowBackground(Color.bg)
                    .listRowSeparatorTint(Color.border.opacity(0.6))
                    .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + (selectionMode ? 118 : 86) }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if !selectionMode {
                            Button { addRef = ExerciseRef(id: ex.id) } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .tint(.accent)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func row(_ ex: Exercise) -> some View {
        if selectionMode {
            Button {
                if selected.contains(ex.id) { selected.remove(ex.id) } else { selected.insert(ex.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selected.contains(ex.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(selected.contains(ex.id) ? Color.accent : Color.text3)
                        .contentTransition(.symbolEffect(.replace))
                    LibraryRow(exercise: ex)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: ExerciseRef(id: ex.id)) {
                LibraryRow(exercise: ex)
            }
        }
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
