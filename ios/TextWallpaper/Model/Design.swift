import Foundation
import CoreGraphics

// Shared contract. Every coordinate and size is a fraction of the wallpaper,
// so the same design renders identically in the preview and the full-res PNG.

struct TextBlock: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var font: FontChoice = .sans
    /// Font size as a fraction of the wallpaper width (0.03...0.2).
    var size: Double = 0.07
    var color: RGBA = .white
    /// Center of the block, 0...1 in both axes (y measured from the top).
    var center: CGPoint = CGPoint(x: 0.5, y: 0.55)
    /// Max line width as a fraction of the wallpaper width; text wraps inside it.
    var width: Double = 0.8
}

enum Background: Codable, Equatable {
    case color(RGBA)
    /// File name inside the app's Documents directory (see DesignStore).
    case photo(String)
}

struct Design: Codable, Equatable {
    var background: Background = .color(RGBA(r: 0.11, g: 0.17, b: 0.29))
    /// 0...0.7 black overlay on photo backgrounds so text stays readable.
    var dim: Double = 0.2
    var blocks: [TextBlock] = [TextBlock(text: "오늘도 수고했어")]
}

// Hand-written decoding so a field added later falls back to its default instead
// of failing the whole file (Encodable stays synthesized).
extension TextBlock {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var b = TextBlock(text: try c.decode(String.self, forKey: .text))
        b.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? b.id
        b.font = try c.decodeIfPresent(FontChoice.self, forKey: .font) ?? b.font
        b.size = try c.decodeIfPresent(Double.self, forKey: .size) ?? b.size
        b.color = try c.decodeIfPresent(RGBA.self, forKey: .color) ?? b.color
        b.center = try c.decodeIfPresent(CGPoint.self, forKey: .center) ?? b.center
        b.width = try c.decodeIfPresent(Double.self, forKey: .width) ?? b.width
        self = b
    }
}

extension Design {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = Design()
        d.background = try c.decodeIfPresent(Background.self, forKey: .background) ?? d.background
        d.dim = try c.decodeIfPresent(Double.self, forKey: .dim) ?? d.dim
        d.blocks = try c.decodeIfPresent([TextBlock].self, forKey: .blocks) ?? d.blocks
        self = d
    }
}

enum FontChoice: String, Codable, CaseIterable, Identifiable {
    case sans, serif, dodum, pen
    var id: String { rawValue }
}

struct RGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double = 1
    static let white = RGBA(r: 1, g: 1, b: 1)
    static let black = RGBA(r: 0, g: 0, b: 0)
}

/// Lock-screen zones as fractions of height, used for the editor's guide overlay.
enum LockZones {
    static let top = 0.35     // clock + widgets
    static let bottom = 0.14  // flashlight / camera
}
