import SwiftUI

// STUB — owned by the editor agent.
struct EditorView: View {
    @StateObject private var store = DesignStore()
    var body: some View { WallpaperView(design: store.design, photo: store.photo) }
}
