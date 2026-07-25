//
//  CustomExerciseForm.swift
//  Replog
//
//  Create or edit a user-defined exercise with the same facets the bundled catalog
//  carries. Everything is required except the photos (up to 5, reorderable). On save it
//  persists the `CustomExercise`, merges it into the catalog, and hands the id back.
//

import SwiftUI
import SwiftData
import PhotosUI

struct CustomExerciseForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// The exercise being edited, or `nil` to create a new one.
    var editing: CustomExercise? = nil
    /// Called with the saved exercise's id.
    var onSave: (String) -> Void = { _ in }

    /// A photo with a stable identity so the list reorders cleanly.
    private struct Photo: Identifiable { let id = UUID(); var data: Data }

    @State private var name = ""
    @State private var category: ExerciseCategory = .strength
    @State private var equipment: Equipment = .bodyOnly
    @State private var force: Force = .push
    @State private var mechanic: Mechanic = .compound
    @State private var level: Level = .beginner
    @State private var primary: Set<Muscle> = []
    @State private var secondary: Set<Muscle> = []
    @State private var instructions = ""
    @State private var photos: [Photo] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var loaded = false

    private let maxPhotos = 5

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty && !primary.isEmpty }
    private var isEditing: Bool { editing != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Exercise name", text: $name).font(.bodyText)
                }

                photoSection

                Section("Details") {
                    facetPicker("Category", $category, ExerciseCategory.allCases) { $0.displayName }
                    facetPicker("Equipment", $equipment, Equipment.allCases) { $0.displayName }
                    facetPicker("Force", $force, Force.allCases) { $0.displayName }
                    facetPicker("Mechanic", $mechanic, Mechanic.allCases) { $0.displayName }
                    facetPicker("Level", $level, Level.allCases) { $0.displayName }
                }

                Section("Primary muscles") { muscleChips($primary, other: $secondary) }
                Section("Secondary muscles (optional)") { muscleChips($secondary, other: $primary) }

                Section("How to (optional)") {
                    TextField("One step per line", text: $instructions, axis: .vertical)
                        .font(.bodyText).lineLimit(3...8)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bg.ignoresSafeArea())
            .tint(Color.accent)
            .navigationTitle(isEditing ? "Edit Exercise" : "New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.text2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.font(.rounded(15, .heavy))
                        .foregroundStyle(isValid ? Color.accent : Color.text3)
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: prefillIfNeeded)
            .onChange(of: pickedItems) { loadPicked() }
        }
    }

    // MARK: Photos

    @ViewBuilder private var photoSection: some View {
        Section {
            // Reorder (long-press drag) and swipe-to-delete — SwiftUI's native list editing.
            ForEach(photos) { photo in
                HStack(spacing: 12) {
                    if let ui = UIImage(data: photo.data) {
                        Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("Photo \((photos.firstIndex(where: { $0.id == photo.id }) ?? 0) + 1)")
                        .font(.rounded(14, .semibold)).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "line.3.horizontal").foregroundStyle(Color.text3)
                }
            }
            .onMove { photos.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { photos.remove(atOffsets: $0) }

            if photos.count < maxPhotos {
                PhotosPicker(selection: $pickedItems, maxSelectionCount: maxPhotos - photos.count, matching: .images) {
                    Label(photos.isEmpty ? "Add photos" : "Add more", systemImage: "photo.badge.plus")
                        .font(.rounded(15, .semibold)).foregroundStyle(Color.accent)
                }
            }
        } header: {
            Text("Photos (optional, up to \(maxPhotos)) — drag to reorder")
        }
    }

    private func facetPicker<T: Hashable>(_ title: String, _ selection: Binding<T>,
                                          _ options: [T], _ label: @escaping (T) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        .font(.bodyText)
    }

    private func muscleChips(_ selection: Binding<Set<Muscle>>, other: Binding<Set<Muscle>>) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(Muscle.allCases) { muscle in
                let on = selection.wrappedValue.contains(muscle)
                Button {
                    if on { selection.wrappedValue.remove(muscle) }
                    else { selection.wrappedValue.insert(muscle); other.wrappedValue.remove(muscle) }
                } label: {
                    Text(muscle.displayName)
                        .font(.rounded(13, .semibold))
                        .foregroundStyle(on ? .white : Color.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(on ? Color.accent : Color.surface2))
                }
                .buttonStyle(.plain)
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
    }

    // MARK: Actions

    private func prefillIfNeeded() {
        guard let editing, !loaded else { return }
        loaded = true
        name = editing.name
        category = editing.category
        equipment = editing.equipment ?? .bodyOnly
        force = editing.force ?? .push
        mechanic = editing.mechanic ?? .compound
        level = editing.level
        primary = Set(editing.primaryMuscles)
        secondary = Set(editing.secondaryMuscles)
        instructions = editing.instructions.joined(separator: "\n")
        photos = editing.imagesData.map { Photo(data: $0) }
    }

    private func save() {
        let steps = instructions
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let images = photos.map(\.data)

        let exercise: CustomExercise
        if let editing {
            exercise = editing
            exercise.name = trimmedName
            exercise.forceRaw = force.rawValue
            exercise.levelRaw = level.rawValue
            exercise.mechanicRaw = mechanic.rawValue
            exercise.equipmentRaw = equipment.rawValue
            exercise.primaryMusclesRaw = primary.map(\.rawValue)
            exercise.secondaryMusclesRaw = secondary.map(\.rawValue)
            exercise.categoryRaw = category.rawValue
            exercise.instructions = steps
            exercise.imagesData = images
        } else {
            exercise = CustomExercise(
                name: trimmedName, force: force, level: level, mechanic: mechanic,
                equipment: equipment, primaryMuscles: Array(primary), secondaryMuscles: Array(secondary),
                category: category, instructions: steps, imagesData: images)
            context.insert(exercise)
        }
        try? context.save()
        context.syncCustomExercises()   // re-merge so the change is visible immediately
        onSave(exercise.id)
        dismiss()
    }

    private func loadPicked() {
        let items = pickedItems
        pickedItems = []
        guard !items.isEmpty else { return }
        Task {
            var added: [Photo] = []
            for item in items where photos.count + added.count < maxPhotos {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    added.append(Photo(data: Self.downscaled(data) ?? data))
                }
            }
            photos.append(contentsOf: added)
        }
    }

    /// Shrink a picked photo to catalog scale (~500 px, JPEG) so the store stays small.
    private static func downscaled(_ data: Data, maxDimension: CGFloat = 500) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }
}
