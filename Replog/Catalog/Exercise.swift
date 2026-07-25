//
//  Exercise.swift
//  Replog
//
//  The static catalog model: one entry from the bundled Free Exercise DB.
//  This is read-only reference data — user data (Plan/Workout/…) lives in SwiftData
//  and references exercises by their `id`.
//

import Foundation

struct Exercise: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let force: Force?
    let level: Level
    let mechanic: Mechanic?
    let equipment: Equipment?
    let primaryMuscles: [Muscle]
    let secondaryMuscles: [Muscle]
    let category: ExerciseCategory
    let instructions: [String]
    /// Relative image paths from the source DB, e.g. "Battling_Ropes/0.jpg".
    /// The bundled assets are HEIC; `imageNames` resolves the shipped filenames.
    let images: [String]
    /// User-supplied photos, for custom exercises only (bundled entries use `images`).
    /// Defaulted so JSON decoding and every existing call site are unaffected.
    var imageDatas: [Data] = []

    /// The first custom photo, if any — for single-image thumbnails.
    var imageData: Data? { imageDatas.first }

    /// All muscles worked (primary first), de-duplicated — handy for chips & filters.
    var allMuscles: [Muscle] {
        var seen = Set<Muscle>()
        return (primaryMuscles + secondaryMuscles).filter { seen.insert($0).inserted }
    }

    /// The flat, globally-unique resource names of the shipped HEIC images
    /// (no extension), e.g. "Battling_Ropes/0.jpg" -> "Battling_Ropes__0".
    /// Matches the output of `Scripts/build-exercise-db.sh`.
    var imageResourceNames: [String] {
        images.map { path in
            let noExt = (path as NSString).deletingPathExtension
            return noExt.replacingOccurrences(of: "/", with: "__")
        }
    }

    /// Every photo to display, source-agnostic: a custom exercise's own photos, else the
    /// bundled ones. The single source of truth for carousels, film strips, and thumbnails.
    var photos: [ExercisePhoto] {
        imageDatas.isEmpty ? imageResourceNames.map(ExercisePhoto.bundled)
                           : imageDatas.map(ExercisePhoto.data)
    }
}

/// One displayable exercise photo — a bundled HEIC resource or user-supplied image data.
/// Lets every image view and carousel treat catalog and custom exercises identically.
enum ExercisePhoto: Hashable, Sendable, Identifiable {
    case bundled(String)
    case data(Data)

    var id: String {
        switch self {
        case .bundled(let name): return "bundled:\(name)"
        case .data(let data):    return "data:\(data.hashValue)"
        }
    }
}

// MARK: - Lenient decoding

extension Exercise: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, force, level, mechanic, equipment
        case primaryMuscles, secondaryMuscles, category, instructions, images
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        force = Self.lenient(try? c.decodeIfPresent(String.self, forKey: .force))
        level = Self.lenient(try? c.decodeIfPresent(String.self, forKey: .level)) ?? .beginner
        mechanic = Self.lenient(try? c.decodeIfPresent(String.self, forKey: .mechanic))
        equipment = Self.lenient(try? c.decodeIfPresent(String.self, forKey: .equipment))
        primaryMuscles = Self.lenientList(try? c.decodeIfPresent([String].self, forKey: .primaryMuscles))
        secondaryMuscles = Self.lenientList(try? c.decodeIfPresent([String].self, forKey: .secondaryMuscles))
        category = Self.lenient(try? c.decodeIfPresent(String.self, forKey: .category)) ?? .strength
        instructions = (try? c.decodeIfPresent([String].self, forKey: .instructions)) ?? []
        images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? []
    }

    /// Maps a possibly-`nil`/"None" string to a RawRepresentable, returning nil on miss.
    private static func lenient<T: RawRepresentable>(_ raw: String??) -> T? where T.RawValue == String {
        guard let value = raw ?? nil, value.lowercased() != "none" else { return nil }
        return T(rawValue: value)
    }

    private static func lenientList<T: RawRepresentable>(_ raw: [String]??) -> [T] where T.RawValue == String {
        guard let list = raw ?? nil else { return [] }
        return list.compactMap { T(rawValue: $0) }
    }
}
