import SwiftUI

// STUB — owned by the core agent.
extension FontChoice {
    var label: String { rawValue }
    func font(size: CGFloat) -> Font { .system(size: size, weight: .bold) }
}
