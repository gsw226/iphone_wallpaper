import SwiftUI

/// The wallpaper itself, used for both the editor preview and the PNG export.
/// Fills its frame; every size and position is a fraction of that frame.
struct WallpaperView: View {
    let design: Design
    let photo: UIImage?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                background(w, h)
                ForEach(design.blocks) { block in
                    Text(block.text)
                        .font(block.font.font(size: block.size * w))
                        .foregroundStyle(block.color.swiftUI)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: block.width * w)
                        .position(x: block.center.x * w, y: block.center.y * h)
                }
            }
        }
    }

    @ViewBuilder private func background(_ w: CGFloat, _ h: CGFloat) -> some View {
        if case .photo = design.background, let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: w, height: h)
                .clipped()
                .overlay(Color.black.opacity(design.dim))
        } else if case .color(let c) = design.background {
            c.swiftUI
        } else {
            Color.black // photo background whose image isn't loaded
        }
    }
}

private extension RGBA {
    var swiftUI: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}
