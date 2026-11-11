import SwiftUI

/// The single current design, persisted as `design.json` (+ one photo JPEG) in `directory`.
@MainActor final class DesignStore: ObservableObject {
    /// Autosaves 0.3 s after the last change, and immediately when the app resigns active.
    @Published var design: Design { didSet { scheduleSave() } }
    @Published private(set) var photo: UIImage?

    private let directory: URL
    private var saveTask: Task<Void, Never>?
    private var designURL: URL { directory.appending(path: "design.json") }

    init(directory: URL = URL.documentsDirectory) {
        self.directory = directory
        var d = (try? Data(contentsOf: directory.appending(path: "design.json")))
            .flatMap { try? JSONDecoder().decode(Design.self, from: $0) } ?? Design()
        var image: UIImage?
        if case .photo(let name) = d.background {
            image = UIImage(contentsOfFile: directory.appending(path: name).path)
            if image == nil { d.background = Design().background }
        }
        design = d
        photo = image
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(design).write(to: designURL, options: .atomic)
    }

    /// Downscales, stores as JPEG under a new name, and makes it the background.
    func setPhoto(_ image: UIImage) {
        let scaled = Self.downscaled(image)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.9) else { return }
        let name = "photo-\(UUID().uuidString).jpg"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? jpeg.write(to: directory.appending(path: name), options: .atomic)) != nil else { return }
        deletePhotoFile()
        photo = scaled
        design.background = .photo(name)
        saveNow()
    }

    func clearPhoto(color: RGBA) {
        deletePhotoFile()
        photo = nil
        design.background = .color(color)
        saveNow()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func deletePhotoFile() {
        if case .photo(let old) = design.background {
            try? FileManager.default.removeItem(at: directory.appending(path: old))
        }
    }

    /// Scale so the image just covers 1.5× the output (enough for aspect-fill crops),
    /// never upscaling. Redrawing also bakes in the EXIF orientation.
    private static func downscaled(_ image: UIImage) -> UIImage {
        let out = WallpaperRenderer.outputSize
        let px = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let s = min(1, max(1.5 * out.width / px.width, 1.5 * out.height / px.height))
        let size = CGSize(width: (px.width * s).rounded(), height: (px.height * s).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
