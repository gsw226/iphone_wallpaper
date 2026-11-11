import SwiftUI
import CoreText

// Bundled OFL fonts (TextWallpaper/Fonts, registered via UIAppFonts).
extension FontChoice {
    var label: String {
        switch self {
        case .sans: "고딕"
        case .serif: "명조"
        case .dodum: "고운돋움"
        case .pen: "손글씨"
        }
    }

    /// Fixed-size font (no Dynamic Type) so preview and export match exactly.
    func font(size: CGFloat) -> Font {
        switch self {
        case .sans: Self.bold("NotoSansKR-Thin", size)
        case .serif: Self.bold("NotoSerifKR-ExtraLight", size)
        case .dodum: .custom("GowunDodum-Regular", fixedSize: size)
        // Nanum Pen draws small for its point size; bump it to sit level with the others.
        case .pen: .custom("NanumPen-Regular", fixedSize: size * 1.3)
        }
    }

    /// The Noto KR files are variable fonts whose default instance is the lightest;
    /// pin the wght axis to 700 explicitly.
    private static func bold(_ postScriptName: String, _ size: CGFloat) -> Font {
        let base = CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString, size)
        let wght = 0x77676874 as CFNumber // 'wght'
        let desc = CTFontDescriptorCreateCopyWithVariation(base, wght, 700)
        return Font(CTFontCreateWithFontDescriptor(desc, size, nil))
    }
}
