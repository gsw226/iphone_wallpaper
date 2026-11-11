import SwiftUI

enum WallpaperRenderer {
    /// Portrait output size in pixels (native screen size, e.g. 1179×2556).
    static var outputSize: CGSize {
        let fallback = CGSize(width: 1179, height: 2556)
        guard Thread.isMainThread else { return fallback }
        let b = MainActor.assumeIsolated { UIScreen.main.nativeBounds.size }
        guard b.width > 0, b.height > 0 else { return fallback }
        return CGSize(width: min(b.width, b.height), height: max(b.width, b.height))
    }

    /// Renders at exactly `outputSize` pixels (scale 1, one point = one pixel).
    @MainActor static func render(_ design: Design, photo: UIImage?) -> UIImage? {
        let size = outputSize
        let renderer = ImageRenderer(content: WallpaperView(design: design, photo: photo)
            .frame(width: size.width, height: size.height))
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    @MainActor static func pngData(_ design: Design, photo: UIImage?) -> Data? {
        render(design, photo: photo)?.pngData()
    }
}
