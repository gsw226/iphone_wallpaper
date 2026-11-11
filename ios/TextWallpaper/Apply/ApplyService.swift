import SwiftUI
import Photos
import UniformTypeIdentifiers

enum ApplyService {
    static let shortcutName = "문장 배경화면"

    /// Hands the PNG to the "문장 배경화면" shortcut via the clipboard, which sets the lock screen.
    /// Returns false when the Shortcuts app can't be opened (touching nothing if that's known up front).
    @MainActor @discardableResult
    static func applyViaShortcut(png: Data) async -> Bool {
        guard let url = shortcutURL, UIApplication.shared.canOpenURL(url) else { return false }
        UIPasteboard.general.setItems(
            [[UTType.png.identifier: png]],
            options: [.expirationDate: Date().addingTimeInterval(120), .localOnly: true]
        )
        return await UIApplication.shared.open(url)
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

    enum SaveResult { case saved, denied, failed }

    /// Saves the PNG to Photos. Completion runs on the main thread; `.denied` means the
    /// user (or a restriction) blocked Photos access, so Settings is the way out.
    @MainActor static func saveToPhotos(png: Data, completion: @escaping (SaveResult) -> Void) {
        let done: (SaveResult) -> Void = { r in DispatchQueue.main.async { completion(r) } }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            switch status {
            case .authorized, .limited: break
            case .denied, .restricted: return done(.denied)
            default: return done(.failed)
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }) { ok, _ in done(ok ? .saved : .failed) }
        }
    }
}
