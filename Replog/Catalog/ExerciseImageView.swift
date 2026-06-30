//
//  ExerciseImageView.swift
//  Replog
//
//  Loads bundled HEIC demo photos with a small in-memory cache and a graceful
//  placeholder. Resource names are the flat, unique names produced by the asset
//  pipeline (see Exercise.imageResourceNames).
//

import SwiftUI

/// Resolves and caches bundled exercise images by their flat resource name.
/// `nonisolated` so cold decodes can run off the main actor.
nonisolated final class ExerciseImageStore: Sendable {
    static let shared = ExerciseImageStore()
    // NSCache is internally thread-safe; mark unsafe to satisfy Sendable checking.
    private nonisolated(unsafe) let cache = NSCache<NSString, UIImage>()

    private init() { cache.countLimit = 240 }

    /// The bundle URL for a flat resource name like "Battling_Ropes__0".
    func url(forResourceName name: String, bundle: Bundle = .main) -> URL? {
        // Primary: flattened into the bundle root.
        bundle.url(forResource: name, withExtension: "heic")
            // Fallback: in case Xcode preserves the folder reference.
            ?? bundle.url(forResource: name, withExtension: "heic", subdirectory: "ExerciseImages")
    }

    func image(forResourceName name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let url = url(forResourceName: name),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}

/// Displays a single exercise photo by resource name, loading off the main thread.
struct ExerciseImageView: View {
    let resourceName: String?
    var cornerRadius: CGFloat = 0

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: resourceName) { await load() }
    }

    private var placeholder: some View {
        ZStack {
            Color.surface2
            Image(systemName: "dumbbell.fill")
                .foregroundStyle(Color.text3)
                .font(.system(size: 18))
        }
    }

    private func load() async {
        guard let resourceName else { image = nil; return }
        // Synchronous cache hit stays instant; cold loads hop off-main.
        if let cached = ExerciseImageStore.shared.image(forResourceName: resourceName) {
            image = cached
            return
        }
        let loaded = await Task.detached(priority: .userInitiated) {
            ExerciseImageStore.shared.image(forResourceName: resourceName)
        }.value
        if !Task.isCancelled { image = loaded }
    }
}

/// Convenience: the first/primary photo of an exercise.
extension ExerciseImageView {
    init(exercise: Exercise, cornerRadius: CGFloat = 0) {
        self.init(resourceName: exercise.imageResourceNames.first, cornerRadius: cornerRadius)
    }
}
