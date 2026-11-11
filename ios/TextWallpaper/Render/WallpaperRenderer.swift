import SwiftUI

// STUB — owned by the core agent.
enum WallpaperRenderer {
    /// Portrait output size in pixels (native screen size, e.g. 1179×2556).
    static var outputSize: CGSize { CGSize(width: 1179, height: 2556) }
    @MainActor static func render(_ design: Design, photo: UIImage?) -> UIImage? { nil }
    @MainActor static func pngData(_ design: Design, photo: UIImage?) -> Data? { nil }
}
