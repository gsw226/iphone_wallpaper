import SwiftUI

/// Root screen: wallpaper preview on top, inspector for the selected block (or the
/// background) below it, and the apply / share / save actions at the bottom.
struct EditorView: View {
    @StateObject private var store = DesignStore()
    @State private var selection: TextBlock.ID?
    @State private var toast: EditorToast?
    @State private var showInfo = false
    @State private var showFirstRunHint = false
    @FocusState private var textFocused: Bool
    @AppStorage("editor.shortcutHintSeen") private var hintSeen = false
    @Environment(\.openURL) private var openURL

    static let shortcutURL = URL(string: "https://gsw226.github.io/iphone_wallpaper/shortcut/%EB%AC%B8%EC%9E%A5%20%EB%B0%B0%EA%B2%BD%ED%99%94%EB%A9%B4.shortcut")!

    var body: some View {
        VStack(spacing: 12) {
            EditorPreview(store: store, selection: $selection)
                .overlay(alignment: .topTrailing) { infoButton }
                .overlay(alignment: .bottom) { toastView }
            Group {
                EditorInspector(store: store, selection: $selection, focus: $textFocused)
                if !textFocused { actionBar }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .onOpenURL { url in
            if let msg = ApplyService.handle(url: url) {
                show(EditorToast(text: msg, symbol: url.host == "done" ? "checkmark" : "exclamationmark.triangle"))
            }
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.selection, trigger: selection)
        .onChange(of: selection) { textFocused = false }
        .alert("단축어가 필요해요", isPresented: $showFirstRunHint) {
            Button("단축어 설치") {
                hintSeen = true
                openURL(Self.shortcutURL)
            }
            Button("이미 설치했어요") {
                hintSeen = true
                apply()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("처음 한 번만 ‘\(ApplyService.shortcutName)’ 단축어를 설치하면 이 버튼으로 잠금 화면 배경을 바로 바꿀 수 있어요.")
        }
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 10) {
            ShareLink(item: EditorShareImage(design: store.design, photo: store.photo),
                      preview: SharePreview("문장 배경화면")) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 24)
            }
            .accessibilityLabel("공유")

            Button(action: save) {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 24)
            }
            .accessibilityLabel("사진에 저장")

            Button {
                if hintSeen { apply() } else { showFirstRunHint = true }
            } label: {
                Text("배경화면으로 설정")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func apply() {
        guard let png = WallpaperRenderer.pngData(store.design, photo: store.photo) else {
            show(EditorToast(text: "이미지를 만들지 못했어요", symbol: "exclamationmark.triangle"))
            return
        }
        if !ApplyService.applyViaShortcut(png: png) {
            show(EditorToast(text: "단축어 앱을 열 수 없어요", symbol: "exclamationmark.triangle"))
        }
    }

    private func save() {
        guard let png = WallpaperRenderer.pngData(store.design, photo: store.photo) else {
            show(EditorToast(text: "이미지를 만들지 못했어요", symbol: "exclamationmark.triangle"))
            return
        }
        ApplyService.saveToPhotos(png: png) { ok in
            Task { @MainActor in
                show(ok ? EditorToast(text: "사진에 저장됨", symbol: "checkmark")
                        : EditorToast(text: "저장하지 못했어요", symbol: "exclamationmark.triangle"))
            }
        }
    }

    // MARK: Feedback

    private func show(_ t: EditorToast) {
        toast = t
        AccessibilityNotification.Announcement(t.text).post()
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == t { toast = nil }
        }
    }

    private var toastView: some View {
        ZStack {
            if let toast {
                Label(toast.text, systemImage: toast.symbol)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.2), value: toast)
        .allowsHitTesting(false)
    }

    private var infoButton: some View {
        Button { showInfo = true } label: {
            Image(systemName: "info.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("단축어 안내")
        .popover(isPresented: $showInfo) {
            VStack(alignment: .leading, spacing: 10) {
                Text("한 번만 설치하면 돼요")
                    .font(.headline)
                Text("‘배경화면으로 설정’은 ‘\(ApplyService.shortcutName)’ 단축어로 잠금 화면 배경을 바꿔요. 처음 한 번 단축어를 설치해 주세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("단축어 설치하기", destination: Self.shortcutURL)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(16)
            .frame(width: 290)
            .presentationCompactAdaptation(.popover)
        }
    }
}

struct EditorToast: Equatable {
    let id = UUID()
    let text: String
    let symbol: String
}

/// Share item that renders the PNG only when the share sheet asks for the data,
/// so editing never pays for a full-resolution render.
struct EditorShareImage: Transferable {
    let design: Design
    let photo: UIImage?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in try await item.png() }
    }

    @MainActor private func png() throws -> Data {
        guard let data = WallpaperRenderer.pngData(design, photo: photo) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
