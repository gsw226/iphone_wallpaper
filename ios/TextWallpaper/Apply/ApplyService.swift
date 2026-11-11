import SwiftUI

// STUB — owned by the apply agent.
enum ApplyService {
    static let shortcutName = "문장 배경화면"
    /// Hands the PNG to the "문장 배경화면" shortcut, which sets the lock screen.
    @MainActor static func applyViaShortcut(png: Data) {}
    /// Saves the PNG to Photos. Completion reports success.
    @MainActor static func saveToPhotos(png: Data, completion: @escaping (Bool) -> Void) { completion(false) }
}

/// For ShareLink fallback.
struct WallpaperPNG: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
    }
}
