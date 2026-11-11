import SwiftUI
import ImageIO

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
        let fm = FileManager.default
        let url = directory.appending(path: "design.json")
        var d = Design()
        var corrupt = false
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode(Design.self, from: data) {
                d = decoded
            } else {
                // Keep the unreadable file out of autosave's way instead of overwriting it.
                corrupt = true
                let bad = directory.appending(path: "design.bad.json")
                try? fm.removeItem(at: bad)
                try? fm.moveItem(at: url, to: bad)
            }
        }
        var image: UIImage?
        if case .photo(let name) = d.background {
            image = UIImage(contentsOfFile: directory.appending(path: name).path)
            if image == nil { d.background = Design().background }
        }
        // Drop photos left behind by an interrupted replace (kept if design.bad.json may still need them).
        if !corrupt {
            var keep: String?
            if case .photo(let name) = d.background { keep = name }
            for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
            where name.hasPrefix("photo-") && name.hasSuffix(".jpg") && name != keep {
                try? fm.removeItem(at: directory.appending(path: name))
            }
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

    /// Decodes and downsizes off the main actor, stores as JPEG under a new name, and
    /// makes it the background. Does nothing if cancelled or if the background changed
    /// meanwhile (the user's later pick wins); throws if the data isn't a usable image.
    func setPhoto(_ data: Data) async throws {
        let before = design.background
        let (image, jpeg) = try await Self.prepared(data, out: WallpaperRenderer.outputSize)
        guard !Task.isCancelled, design.background == before else { return }
        let name = "photo-\(UUID().uuidString).jpg"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: directory.appending(path: name), options: .atomic)
        let old = design.background
        photo = image
        design.background = .photo(name)
        saveNow()
        deletePhotoFile(old)
    }

    func clearPhoto(color: RGBA) {
        let old = design.background
        photo = nil
        design.background = .color(color)
        saveNow()
        deletePhotoFile(old)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func deletePhotoFile(_ background: Background) {
        if case .photo(let old) = background {
            try? FileManager.default.removeItem(at: directory.appending(path: old))
        }
    }

    /// Downsamples with ImageIO (orientation baked in) so the result still covers 1.5×
    /// `out` once center-cropped to the output aspect ratio, then does that crop: the
    /// aspect-fill background is always centered, so nothing visible is lost.
    nonisolated private static func prepared(_ data: Data, out: CGSize) async throws -> (UIImage, Data) {
        let fail = CocoaError(.fileReadCorruptFile)
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let pw = props[kCGImagePropertyPixelWidth] as? Int,
              let ph = props[kCGImagePropertyPixelHeight] as? Int, pw > 0, ph > 0
        else { throw fail }
        let rotated = (props[kCGImagePropertyOrientation] as? Int ?? 1) >= 5
        let w = CGFloat(rotated ? ph : pw), h = CGFloat(rotated ? pw : ph)
        let s = min(1, max(1.5 * out.width / w, 1.5 * out.height / h))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int((s * max(w, h)).rounded(.up)),
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { throw fail }
        let tw = CGFloat(thumb.width), th = CGFloat(thumb.height), ratio = out.width / out.height
        let cw = min(tw, (th * ratio).rounded()), ch = min(th, (tw / ratio).rounded())
        // Redraw into a fresh bitmap so the (possibly huge) thumbnail buffer is released.
        guard let ctx = CGContext(data: nil, width: Int(cw), height: Int(ch), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.displayP3)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw fail }
        ctx.draw(thumb, in: CGRect(x: ((cw - tw) / 2).rounded(), y: ((ch - th) / 2).rounded(), width: tw, height: th))
        guard let cropped = ctx.makeImage() else { throw fail }
        let image = UIImage(cgImage: cropped)
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { throw fail }
        return (image, jpeg)
    }
}
