import SwiftUI

// STUB — owned by the core agent.
@MainActor final class DesignStore: ObservableObject {
    @Published var design = Design()
    @Published private(set) var photo: UIImage?
    init(directory: URL = URL.documentsDirectory) {}
    func setPhoto(_ image: UIImage) {}
    func clearPhoto(color: RGBA) { design.background = .color(color) }
}
