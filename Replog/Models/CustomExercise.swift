//
//  CustomExercise.swift
//  Replog
//
//  A user-created exercise. Persisted in SwiftData, then merged into `ExerciseCatalog`
//  at launch and on change so it resolves by `exId` exactly like a bundled Free Exercise
//  DB entry — usable in workouts, the live log, stats, and bodyweight detection.
//

import Foundation
import SwiftData

@Model
final class CustomExercise {
    /// Stable catalog id (e.g. "custom-<uuid>"). `PlanItem.exId` references this, so it
    /// must never change once a workout uses the exercise.
    @Attribute(.unique) var id: String = ""
    var name: String = ""
    // Enum facets stored as raw strings (SwiftData-friendly); `asExercise` types them back.
    var forceRaw: String?
    var levelRaw: String = Level.beginner.rawValue
    var mechanicRaw: String?
    var equipmentRaw: String?
    var primaryMusclesRaw: [String] = []
    var secondaryMusclesRaw: [String] = []
    var categoryRaw: String = ExerciseCategory.strength.rawValue
    var instructions: [String] = []
    /// Up to 5 user photos, in display order. Kept out of the main store file so the
    /// images never bloat it.
    @Attribute(.externalStorage) var imagesData: [Data] = []
    var createdAt: Date = Date()

    init(id: String = "custom-\(UUID().uuidString)", name: String,
         force: Force?, level: Level, mechanic: Mechanic?, equipment: Equipment?,
         primaryMuscles: [Muscle], secondaryMuscles: [Muscle] = [],
         category: ExerciseCategory, instructions: [String] = [], imagesData: [Data] = []) {
        self.id = id
        self.name = name
        self.forceRaw = force?.rawValue
        self.levelRaw = level.rawValue
        self.mechanicRaw = mechanic?.rawValue
        self.equipmentRaw = equipment?.rawValue
        self.primaryMusclesRaw = primaryMuscles.map(\.rawValue)
        self.secondaryMusclesRaw = secondaryMuscles.map(\.rawValue)
        self.categoryRaw = category.rawValue
        self.instructions = instructions
        self.imagesData = imagesData
    }

    /// Typed facets, for pre-filling the edit form.
    var force: Force? { forceRaw.flatMap(Force.init(rawValue:)) }
    var level: Level { Level(rawValue: levelRaw) ?? .beginner }
    var mechanic: Mechanic? { mechanicRaw.flatMap(Mechanic.init(rawValue:)) }
    var equipment: Equipment? { equipmentRaw.flatMap(Equipment.init(rawValue:)) }
    var primaryMuscles: [Muscle] { primaryMusclesRaw.compactMap(Muscle.init(rawValue:)) }
    var secondaryMuscles: [Muscle] { secondaryMusclesRaw.compactMap(Muscle.init(rawValue:)) }
    var category: ExerciseCategory { ExerciseCategory(rawValue: categoryRaw) ?? .strength }

    /// The catalog view of this custom exercise, so every reader (lookup, log, Progress,
    /// `BodyweightLoad`) treats it identically to a bundled entry.
    var asExercise: Exercise {
        Exercise(
            id: id,
            name: name,
            force: force,
            level: level,
            mechanic: mechanic,
            equipment: equipment,
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            category: category,
            instructions: instructions,
            images: [],
            imageDatas: imagesData
        )
    }
}
