import SwiftUI
import PhotosUI

/// Bottom panel: edits the selected sentence, or the background when nothing is selected.
/// Both panes share one ZStack so switching never changes the panel's height (and the
/// preview above it never jumps).
struct EditorInspector: View {
    @ObservedObject var store: DesignStore
    @Binding var selection: TextBlock.ID?
    var focus: FocusState<Bool>.Binding

    @State private var photoItem: PhotosPickerItem?
    @State private var lastColor = Self.defaultColor
    @ScaledMetric(relativeTo: .body) private var chipFontSize: CGFloat = 17

    static let maxBlocks = 8
    private static let defaultColor: RGBA = {
        if case .color(let c) = Design().background { return c }
        return .black
    }()

    private enum Pane: Hashable { case text, background }

    var body: some View {
        VStack(spacing: 14) {
            header
            ZStack(alignment: .top) {
                textPane.paneHidden(currentPane != .text)
                if !focus.wrappedValue {
                    backgroundPane.paneHidden(currentPane != .background)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: currentPane)
        .onAppear {
            if case .color(let c) = store.design.background { lastColor = c }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    store.setPhoto(image)
                }
                photoItem = nil
            }
        }
    }

    // MARK: Header

    private var currentPane: Pane { selection == nil ? .background : .text }

    private var paneBinding: Binding<Pane> {
        Binding(
            get: { currentPane },
            set: { pane in
                switch pane {
                case .background:
                    selection = nil
                case .text:
                    guard selection == nil else { return }
                    if let last = store.design.blocks.last { selection = last.id } else { addBlock() }
                }
            })
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("편집 대상", selection: paneBinding) {
                Text("문장").tag(Pane.text)
                Text("배경").tag(Pane.background)
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer(minLength: 0)

            if focus.wrappedValue {
                Button("완료") { focus.wrappedValue = false }
                    .fontWeight(.semibold)
            } else {
                if selection != nil {
                    Button(role: .destructive, action: deleteSelected) {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("문장 삭제")
                }
                Button(action: addBlock) {
                    Label("문장 추가", systemImage: "plus")
                }
                .disabled(store.design.blocks.count >= Self.maxBlocks)
            }
        }
        .frame(minHeight: 32)
    }

    // MARK: Sentence pane

    private var block: Binding<TextBlock> {
        guard let id = selection, store.design.blocks.contains(where: { $0.id == id }) else {
            return .constant(TextBlock(text: ""))
        }
        return Binding(
            get: { store.design.blocks.first { $0.id == id } ?? TextBlock(text: "") },
            set: { new in
                if let i = store.design.blocks.firstIndex(where: { $0.id == id }) { store.design.blocks[i] = new }
            })
    }

    private var textPane: some View {
        VStack(spacing: 14) {
            TextField("문장을 입력하세요", text: block.text, axis: .vertical)
                .lineLimit(2, reservesSpace: true)
                .focused(focus)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 6) {
                ForEach(FontChoice.allCases) { fontChip($0) }
                ColorPicker("글자 색", selection: colorBinding(block.color), supportsOpacity: false)
                    .labelsHidden()
                    .padding(.leading, 6)
            }

            if !focus.wrappedValue {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    sliderRow("크기", accessibility: "글자 크기", value: block.size, in: 0.03...0.2)
                    sliderRow("줄 너비", accessibility: "줄 너비", value: block.width, in: 0.3...0.95)
                }
            }
        }
    }

    private func fontChip(_ choice: FontChoice) -> some View {
        let on = block.wrappedValue.font == choice
        return Button { block.wrappedValue.font = choice } label: {
            Text(choice.label)
                .font(choice.font(size: chipFontSize))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(on ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(on ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: on ? 1.5 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("글꼴 \(choice.label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func sliderRow(_ title: String, accessibility: String, value: Binding<Double>,
                           in range: ClosedRange<Double>) -> some View {
        GridRow {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: value, in: range)
                .accessibilityLabel(accessibility)
        }
    }

    // MARK: Background pane

    private var hasPhoto: Bool {
        if case .photo = store.design.background { return true }
        return false
    }

    private var backgroundColor: Binding<RGBA> {
        Binding(
            get: {
                if case .color(let c) = store.design.background { return c }
                return lastColor
            },
            set: { c in
                lastColor = c
                if hasPhoto { store.clearPhoto(color: c) } else { store.design.background = .color(c) }
            })
    }

    private var backgroundPane: some View {
        VStack(spacing: 0) {
            LabeledContent("배경 색") {
                ColorPicker("배경 색", selection: colorBinding(backgroundColor), supportsOpacity: false)
                    .labelsHidden()
            }
            .frame(minHeight: 44)

            Divider()

            LabeledContent("사진") {
                HStack(spacing: 16) {
                    if hasPhoto {
                        Button("지우기", role: .destructive) { store.clearPhoto(color: lastColor) }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(hasPhoto ? "다른 사진" : "사진 선택")
                    }
                }
            }
            .frame(minHeight: 44)

            if hasPhoto {
                Divider()
                LabeledContent("어둡게") {
                    Slider(value: $store.design.dim, in: 0...0.7)
                        .accessibilityLabel("사진 어둡게")
                        .frame(maxWidth: 200)
                }
                .frame(minHeight: 44)
            }
        }
    }

    // MARK: Block list

    private func addBlock() {
        var new = TextBlock(text: "새 문장")
        if let last = store.design.blocks.last {
            new.font = last.font
            new.size = last.size
            new.color = last.color
            new.width = last.width
            var y = last.center.y + 0.09
            if y > 1 - LockZones.bottom - 0.05 { y = LockZones.top + 0.06 }
            new.center = CGPoint(x: last.center.x, y: y)
        }
        store.design.blocks.append(new)
        selection = new.id
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        store.design.blocks.removeAll { $0.id == id }
        selection = nil
    }
}

// MARK: Helpers

private func colorBinding(_ rgba: Binding<RGBA>) -> Binding<Color> {
    Binding(
        get: {
            let c = rgba.wrappedValue
            return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
        },
        set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            // Extended-range colors from the picker can fall outside 0...1.
            rgba.wrappedValue = RGBA(r: min(max(r, 0), 1), g: min(max(g, 0), 1), b: min(max(b, 0), 1), a: 1)
        })
}

private extension View {
    /// Keeps the layout space (so the panel height stays constant) but removes the
    /// pane from sight, touch and VoiceOver.
    func paneHidden(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}
