//
//  LibraryView.swift
//  Replog
//
//  Browse the full 800+ catalog: search, equipment filter chips, and rows that
//  open the Guide-only exercise detail.
//

import SwiftUI

struct LibraryView: View {
    @Environment(\.exerciseCatalog) private var catalog
    @State private var query = ""
    @State private var filter: EquipmentFilter = .all

    private var results: [Exercise] {
        catalog.search(query, equipment: filter.equipment)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Library").font(.screenTitle).foregroundStyle(Color.textPrimary)
                    searchField
                    filterChips
                    Text("\(results.count) exercises")
                        .font(.rounded(12, .heavy)).textCase(.uppercase).tracking(1.1)
                        .foregroundStyle(Color.text3)
                }
                .padding(.horizontal, 20)

                List {
                    ForEach(results) { ex in
                        NavigationLink(value: ExerciseRef(id: ex.id)) {
                            LibraryRow(exercise: ex)
                        }
                        .listRowBackground(Color.bg)
                        .listRowSeparatorTint(Color.border)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
            .background(Color.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ExerciseRef.self) { ref in
                ExerciseDetailView(exId: ref.id, showProgress: false)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.text3)
            TextField("Search 800+ exercises", text: $query)
                .font(.bodyText).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface2))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EquipmentFilter.allCases) { f in
                    Button { filter = f } label: {
                        Text(f.label)
                            .font(.rounded(13, .heavy))
                            .foregroundStyle(filter == f ? .white : Color.text2)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(filter == f ? Color.accent : Color.surface2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Equipment filter

enum EquipmentFilter: String, CaseIterable, Identifiable {
    case all, barbell, dumbbell, cable, machine, bodyweight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .bodyweight: return "Bodyweight"
        default: return rawValue.capitalized
        }
    }
    var equipment: Equipment? {
        switch self {
        case .all: return nil
        case .barbell: return .barbell
        case .dumbbell: return .dumbbell
        case .cable: return .cable
        case .machine: return .machine
        case .bodyweight: return .bodyOnly
        }
    }
}

// MARK: - Row

private struct LibraryRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 14) {
            ExerciseImageView(exercise: exercise, cornerRadius: 14)
                .frame(width: 60, height: 60)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name).font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary).lineLimit(1)
                Text(subtitle).font(.rounded(12, .semibold)).foregroundStyle(Color.text2).lineLimit(1)
                LevelBadge(level: exercise.level)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        let equip = exercise.equipment?.displayName ?? "Bodyweight"
        let muscle = exercise.primaryMuscles.first?.displayName ?? ""
        return muscle.isEmpty ? equip : "\(equip) · \(muscle)"
    }
}
