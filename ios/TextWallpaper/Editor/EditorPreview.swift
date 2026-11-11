import SwiftUI

/// The wallpaper at the exact output aspect ratio, plus editor-only chrome
/// (lock-screen guide, selection outline, hit targets). None of the chrome lives
/// in WallpaperView, so none of it reaches the exported PNG.
struct EditorPreview: View {
    @ObservedObject var store: DesignStore
    @Binding var selection: TextBlock.ID?
    @State private var dragStart: CGPoint?
    @State private var pinchStart: Double?

    var body: some View {
        GeometryReader { geo in
            let size = Self.fit(geo.size)
            canvas(size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .frame(minHeight: 120)
    }

    static func fit(_ box: CGSize) -> CGSize {
        let out = WallpaperRenderer.outputSize
        let ratio = out.width / out.height
        return box.width / max(box.height, 1) > ratio
            ? CGSize(width: box.height * ratio, height: box.height)
            : CGSize(width: box.width, height: box.width / ratio)
    }

    private func canvas(_ size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.width * 0.11, style: .continuous)
        return ZStack {
            WallpaperView(design: store.design, photo: store.photo)
                .accessibilityHidden(true)
            LockGuide(size: size)
            ForEach(store.design.blocks) { block in
                handle(block, in: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(.named(Self.space))
        .contentShape(shape)
        .onTapGesture { selection = nil }
        .simultaneousGesture(pinch)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private static let space = "editor-canvas"

    // MARK: Blocks

    /// Invisible copy of the block laid out exactly like WallpaperView draws it
    /// (same font, size and wrap width, centered at `center`), used for hit-testing
    /// and the selection outline.
    private func handle(_ block: TextBlock, in size: CGSize) -> some View {
        let selected = block.id == selection
        return Text(block.text.isEmpty ? " " : block.text)
            .font(block.font.font(size: block.size * size.width))
            .multilineTextAlignment(.center)
            .wrapWidth(block.width * size.width)
            .hidden()
            .padding(6)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white, lineWidth: 1.5)
                    .shadow(color: .black.opacity(0.4), radius: 1.5)
                    .opacity(selected ? 1 : 0)
            }
            .frame(minWidth: 44, minHeight: 44)
            .overlay { Color.clear.contentShape(Rectangle()) }
            .onTapGesture { selection = block.id }
            .gesture(drag(block.id, in: size))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(block.text.isEmpty ? "빈 문장" : block.text)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("선택하면 아래에서 편집할 수 있어요")
            .accessibilityAction { selection = block.id }
            .accessibilityAdjustableAction { direction in
                guard let i = index(block.id) else { return }
                let step = direction == .increment ? 0.01 : -0.01
                store.design.blocks[i].size = (store.design.blocks[i].size + step).clamped(0.03, 0.2)
            }
            .zIndex(selected ? 1 : 0)
            .position(x: block.center.x * size.width, y: block.center.y * size.height)
    }

    private func index(_ id: TextBlock.ID) -> Int? {
        store.design.blocks.firstIndex { $0.id == id }
    }

    private func drag(_ id: TextBlock.ID, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard let i = index(id) else { return }
                if dragStart == nil {
                    dragStart = store.design.blocks[i].center
                    selection = id
                }
                guard let start = dragStart else { return }
                store.design.blocks[i].center = CGPoint(
                    x: (start.x + value.translation.width / size.width).clamped(0, 1),
                    y: (start.y + value.translation.height / size.height).clamped(0, 1))
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Pinch anywhere on the preview resizes the selected block; a small block is
    /// too small a target for two fingers.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let id = selection, let i = index(id) else { return }
                if pinchStart == nil { pinchStart = store.design.blocks[i].size }
                guard let start = pinchStart else { return }
                store.design.blocks[i].size = (start * value.magnification).clamped(0.03, 0.2)
            }
            .onEnded { _ in pinchStart = nil }
    }
}

/// Faint stand-in for the system clock (top band) and the flashlight / camera
/// buttons (bottom band), so the user can keep sentences clear of them.
private struct LockGuide: View {
    let size: CGSize

    var body: some View {
        ZStack {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: size.width * 0.23, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.3))
                    .position(x: size.width / 2, y: size.height * LockZones.top * 0.55)
            }
            ForEach(Array(["flashlight.off.fill", "camera.fill"].enumerated()), id: \.offset) { i, symbol in
                let d = size.width * 0.13
                Circle()
                    .fill(.white.opacity(0.12))
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: d * 0.4))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .frame(width: d, height: d)
                    .position(x: size.width * (i == 0 ? 0.18 : 0.82),
                              y: size.height * (1 - LockZones.bottom / 2))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Proposes a fixed width to its content and takes the content's own size, so a
/// short line gets a tight outline while long text still wraps at `width`.
private struct WrapWidth: Layout {
    let width: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                              proposal: ProposedViewSize(width: width, height: nil))
    }
}

private extension View {
    func wrapWidth(_ width: CGFloat) -> some View { WrapWidth(width: width) { self } }
}

private extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
