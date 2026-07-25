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
    @State private var showCustomForm = false

    private var results: [Exercise] {
        catalog.search(query)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                List {
                    createCustomRow
                        .listRowBackground(Color.surface)
                        .listRowSeparatorTint(Color.border)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 16))
                    ForEach(results) { ex in
                        row(ex)
                            .listRowBackground(Color.surface)
                            .listRowSeparatorTint(Color.border)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 16))
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
        .sheet(isPresented: $showCustomForm) {
            CustomExerciseForm { newID in
                added.insert(newID)
                onAdd(newID)   // add the new movement straight into the workout
            }
        }
    }

    /// Entry point to build your own movement when the catalog doesn't have it.
    private var createCustomRow: some View {
        Button { showCustomForm = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentSoft)
                    Image(systemName: "plus").font(.system(size: 20, weight: .black)).foregroundStyle(Color.accent)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create custom exercise").font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                    Text("Add your own movement").font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.text3)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
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
        return HStack(spacing: 14) {
            ExerciseThumbnail(exercise: ex, size: 52, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 4) {
                Text(ex.name).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                Text(subtitle(ex)).font(.rounded(12, .semibold)).foregroundStyle(Color.text2).lineLimit(1)
            }
            Spacer(minLength: 8)
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
        .padding(.vertical, 6)
    }

    private func subtitle(_ ex: Exercise) -> String {
        let equip = ex.equipment?.displayName ?? "Bodyweight"
        let muscle = ex.primaryMuscles.first?.displayName ?? ""
        return muscle.isEmpty ? equip : "\(equip) · \(muscle)"
    }
}
