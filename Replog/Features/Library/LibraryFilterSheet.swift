//
//  LibraryFilterSheet.swift
//  Replog
//
//  Multi-select filter sheet covering every Free Exercise DB facet: level,
//  equipment, force, type (category), mechanic, and muscles worked.
//

import SwiftUI

struct LibraryFilterSheet: View {
    @Bindable var model: LibraryViewModel
    let resultCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Level", Level.allCases,
                            isOn: { model.filter.levels.contains($0) },
                            toggle: { model.filter.levels.toggleMember($0) },
                            label: { $0.displayName })
                    section("Equipment", Equipment.allCases,
                            isOn: { model.filter.equipment.contains($0) },
                            toggle: { model.filter.equipment.toggleMember($0) },
                            label: { $0.displayName })
                    section("Force", Force.allCases,
                            isOn: { model.filter.forces.contains($0) },
                            toggle: { model.filter.forces.toggleMember($0) },
                            label: { $0.displayName })
                    section("Type", ExerciseCategory.allCases,
                            isOn: { model.filter.categories.contains($0) },
                            toggle: { model.filter.categories.toggleMember($0) },
                            label: { $0.displayName })
                    section("Mechanic", Mechanic.allCases,
                            isOn: { model.filter.mechanics.contains($0) },
                            toggle: { model.filter.mechanics.toggleMember($0) },
                            label: { $0.displayName })
                    section("Muscles Worked", Muscle.allCases,
                            caption: "Shows exercises that train every selected muscle (primary or secondary).",
                            isOn: { model.filter.muscles.contains($0) },
                            toggle: { model.filter.muscles.toggleMember($0) },
                            label: { $0.displayName })
                }
                .padding(20)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear all") { model.clearFilter() }
                        .font(.rounded(15, .heavy)).foregroundStyle(Color.text2)
                        .disabled(model.filter.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text(resultCount == 1 ? "Show 1 exercise" : "Show \(resultCount) exercises")
                        .font(.rounded(16, .heavy)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accent))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Facet section

    @ViewBuilder
    private func section<T: Identifiable>(_ title: String, _ options: [T],
                                          caption: String? = nil,
                                          isOn: @escaping (T) -> Bool,
                                          toggle: @escaping (T) -> Void,
                                          label: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            if let caption {
                Text(caption).font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 8) {
                ForEach(options) { option in
                    FilterChip(label: label(option), isSelected: isOn(option)) { toggle(option) }
                }
            }
        }
    }
}

/// A selectable multi-select filter chip (accent when on, surface when off).
private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.rounded(13, .heavy))
                .foregroundStyle(isSelected ? .white : Color.text2)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? Color.accent : Color.surface2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

private extension Set {
    /// Inserts `member` if absent, removes it if present.
    mutating func toggleMember(_ member: Element) {
        if contains(member) { remove(member) } else { insert(member) }
    }
}
