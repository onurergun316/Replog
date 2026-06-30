//
//  AddExercisePicker.swift
//  Replog
//
//  Bottom sheet to search the 800+ catalog and add a movement to the current
//  workout. Context-aware: exercises already present show a check, not a "+".
//

import SwiftUI

struct AddExercisePicker: View {
    @Environment(\.exerciseCatalog) private var catalog
    @Environment(\.dismiss) private var dismiss

    /// Exercise ids already in the workout/session (shown as added).
    let existingIDs: Set<String>
    let onAdd: (String) -> Void

    @State private var query = ""
    @State private var added: Set<String> = []

    private var results: [Exercise] {
        catalog.search(query)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                List {
                    ForEach(results) { ex in
                        row(ex)
                            .listRowBackground(Color.surface)
                            .listRowSeparatorTint(Color.border)
                    }
                }
                .listStyle(.plain)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.rounded(15, .heavy))
                }
            }
        }
        .presentationDetents([.large])
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.text3)
            TextField("Search 800+ exercises", text: $query)
                .font(.bodyText).textInputAutocapitalization(.never)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface2))
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func row(_ ex: Exercise) -> some View {
        let isAdded = existingIDs.contains(ex.id) || added.contains(ex.id)
        return HStack(spacing: 12) {
            ExerciseImageView(exercise: ex, cornerRadius: 10)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                Text(subtitle(ex)).font(.rounded(12, .semibold)).foregroundStyle(Color.text2).lineLimit(1)
            }
            Spacer()
            Button {
                added.insert(ex.id)
                onAdd(ex.id)
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isAdded ? Color.up : Color.accent)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
        }
        .padding(.vertical, 4)
    }

    private func subtitle(_ ex: Exercise) -> String {
        let equip = ex.equipment?.displayName ?? "Bodyweight"
        let muscle = ex.primaryMuscles.first?.displayName ?? ""
        return muscle.isEmpty ? equip : "\(equip) · \(muscle)"
    }
}
