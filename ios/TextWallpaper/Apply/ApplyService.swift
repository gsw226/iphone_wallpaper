import SwiftUI
import Photos
import UniformTypeIdentifiers

enum ApplyService {
    static let shortcutName = "문장 배경화면"

    /// Hands the PNG to the "문장 배경화면" shortcut via the clipboard, which sets the lock screen.
    /// Returns false (and touches nothing) when the Shortcuts app can't be opened.
    @MainActor @discardableResult
    static func applyViaShortcut(png: Data) -> Bool {
        guard let url = shortcutURL, UIApplication.shared.canOpenURL(url) else { return false }
        UIPasteboard.general.setItems(
            [[UTType.png.identifier: png]],
            options: [.expirationDate: Date().addingTimeInterval(120), .localOnly: true]
        )
        UIApplication.shared.open(url)
        return true
    }

    static var shortcutURL: URL? {
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        c.queryItems = [
            URLQueryItem(name: "name", value: shortcutName),
            URLQueryItem(name: "input", value: "clipboard"),
            URLQueryItem(name: "x-success", value: "textwallpaper://done"),
            URLQueryItem(name: "x-error", value: "textwallpaper://error"),
        ]
        // URLComponents leaves ':' and '/' in query values; encode them so nested URLs survive.
        c.percentEncodedQuery = c.percentEncodedQuery?
            .replacingOccurrences(of: ":", with: "%3A")
            .replacingOccurrences(of: "/", with: "%2F")
        return c.url
    }

    /// Maps the x-callback return URL to a status message; nil if the URL isn't ours.
    static func handle(url: URL) -> String? {
        guard url.scheme == "textwallpaper" else { return nil }
        switch url.host {
        case "done": return "잠금 화면에 적용했어요."
        case "error":
            let msg = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "errorMessage" }?.value
            return "적용하지 못했어요." + (msg.map { " (\($0))" } ?? "")
        default: return nil
        }
    }

    /// Saves the PNG to Photos. Completion reports success, on the main thread.
    @MainActor static func saveToPhotos(png: Data, completion: @escaping (Bool) -> Void) {
        let done: (Bool) -> Void = { ok in DispatchQueue.main.async { completion(ok) } }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return done(false) }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }) { ok, _ in done(ok) }
        }
    }
}
