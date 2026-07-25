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
    /// A user photo for custom exercises. Takes precedence over `resourceName` when set.
    var imageData: Data? = nil
    var cornerRadius: CGFloat = 0
    /// `.fill` crops to fill the frame (thumbnails); `.fit` shows the whole photo
    /// letterboxed (detail hero, so no part of the movement is cropped away).
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        // `Color.clear` establishes the frame the caller proposes; the image is drawn as
        // an overlay and clipped to that frame. A `.fill` image overflows the overlay but
        // is cropped by `clipShape` to the exact bounds — so it never bleeds past its
        // frame (the old ZStack let it overflow, which made border overlays land on a
        // mismatched, inset rectangle — the "white square" artifact).
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: resourceName) { await load() }
            .task(id: imageData) { await load() }
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
        // A custom exercise's own photo wins over any bundled resource.
        if let imageData, let custom = UIImage(data: imageData) { image = custom; return }
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
        self.init(resourceName: exercise.imageResourceNames.first,
                  imageData: exercise.imageData, cornerRadius: cornerRadius)
    }

    /// Render a single source-agnostic photo (bundled resource or custom data).
    init(photo: ExercisePhoto?, cornerRadius: CGFloat = 0, contentMode: ContentMode = .fill) {
        switch photo {
        case .bundled(let name):
            self.init(resourceName: name, cornerRadius: cornerRadius, contentMode: contentMode)
        case .data(let data):
            self.init(resourceName: nil, imageData: data, cornerRadius: cornerRadius, contentMode: contentMode)
        case nil:
            self.init(resourceName: nil, cornerRadius: cornerRadius, contentMode: contentMode)
        }
    }
}

/// A uniform square exercise thumbnail. Used everywhere a small photo appears in a
/// list or row so every thumbnail is identical in size, corner radius, and border —
/// fill-cropped to a square regardless of the source photo's orientation.
struct ExerciseThumbnail: View {
    let resourceName: String?
    var imageData: Data? = nil
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12

    var body: some View {
        // Frame → fill-cropped image (clipped to the same rounded rect inside
        // ExerciseImageView) → one hairline on the exact same edge. Everything shares the
        // frame, so nothing is inset or mismatched.
        ExerciseImageView(resourceName: resourceName, imageData: imageData,
                          cornerRadius: cornerRadius, contentMode: .fill)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.border.opacity(0.6), lineWidth: 0.5)
            )
    }
}

extension ExerciseThumbnail {
    init(exercise: Exercise?, size: CGFloat = 52, cornerRadius: CGFloat = 12) {
        self.init(resourceName: exercise?.imageResourceNames.first,
                  imageData: exercise?.imageData, size: size, cornerRadius: cornerRadius)
    }

    /// A single source-agnostic photo (bundled resource or custom data).
    init(photo: ExercisePhoto?, size: CGFloat = 52, cornerRadius: CGFloat = 12) {
        switch photo {
        case .bundled(let name):
            self.init(resourceName: name, size: size, cornerRadius: cornerRadius)
        case .data(let data):
            self.init(resourceName: nil, imageData: data, size: size, cornerRadius: cornerRadius)
        case nil:
            self.init(resourceName: nil, size: size, cornerRadius: cornerRadius)
        }
    }
}
