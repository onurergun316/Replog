//
//  CustomExerciseForm.swift
//  Replog
//
//  Create a user-defined exercise with the same facets the bundled catalog carries.
//  Everything is required except the photo. On save it persists a `CustomExercise`,
//  merges it into the catalog, and hands the new id back to add it to the workout.
//

import SwiftUI
import SwiftData
import PhotosUI

struct CustomExerciseForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Called with the new exercise's id once it's saved.
    let onCreate: (String) -> Void

    @State private var name = ""
    @State private var category: ExerciseCategory = .strength
    @State private var equipment: Equipment = .bodyOnly
    @State private var force: Force = .push
    @State private var mechanic: Mechanic = .compound
    @State private var level: Level = .beginner
    @State private var primary: Set<Muscle> = []
    @State private var secondary: Set<Muscle> = []
    @State private var instructions = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var imageData: Data?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Everything except the photo is required; a movement needs a name and at least one
    /// primary muscle to be worth anything in the log and the stats.
    private var isValid: Bool { !trimmedName.isEmpty && !primary.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Exercise name", text: $name)
                        .font(.bodyText)
                }

                Section("Photo (optional)") { photoRow }

                Section("Details") {
                    picker("Category", $category, ExerciseCategory.allCases) { $0.displayName }
                    picker("Equipment", $equipment, Equipment.allCases) { $0.displayName }
                    picker("Force", $force, Force.allCases) { $0.displayName }
                    picker("Mechanic", $mechanic, Mechanic.allCases) { $0.displayName }
                    picker("Level", $level, Level.allCases) { $0.displayName }
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
            .navigationTitle("New Exercise")
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
            .onChange(of: photoItem) { loadPhoto() }
        }
    }

    // MARK: Rows

    @ViewBuilder private var photoRow: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            HStack(spacing: 12) {
                if let imageData, let ui = UIImage(data: imageData) {
                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface2)
                        Image(systemName: "photo.badge.plus").foregroundStyle(Color.text3)
                    }
                    .frame(width: 52, height: 52)
                }
                Text(imageData == nil ? "Add a photo" : "Change photo")
                    .font(.rounded(15, .semibold)).foregroundStyle(Color.accent)
                Spacer()
            }
        }
        if imageData != nil {
            Button(role: .destructive) { imageData = nil; photoItem = nil } label: {
                Text("Remove photo").font(.rounded(14, .semibold))
            }
        }
    }

    private func picker<T: Hashable>(_ title: String, _ selection: Binding<T>,
                                     _ options: [T], _ label: @escaping (T) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        .font(.bodyText)
    }

    /// Tappable muscle chips. Selecting a muscle here removes it from the other set so a
    /// muscle is never both primary and secondary.
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

    private func save() {
        let steps = instructions
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let exercise = CustomExercise(
            name: trimmedName, force: force, level: level, mechanic: mechanic,
            equipment: equipment, primaryMuscles: Array(primary), secondaryMuscles: Array(secondary),
            category: category, instructions: steps, imageData: imageData)
        context.insert(exercise)
        try? context.save()
        context.syncCustomExercises()   // merge into the catalog so it's usable immediately
        onCreate(exercise.id)
        dismiss()
    }

    private func loadPhoto() {
        guard let photoItem else { return }
        Task {
            guard let data = try? await photoItem.loadTransferable(type: Data.self) else { return }
            imageData = Self.downscaled(data) ?? data
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
