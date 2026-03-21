import SwiftUI

@MainActor
@Observable
final class NotchViewModel {
    var isMouseInside = false
    var isElevated = false
    var isQuickPeeking = false

    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 0

    private let log = FileLog()
    private var elevateTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    // Ghidra-confirmed spring: response=0.35, bounce varies by state
    // Ghidra-confirmed: response=0.35, bounce=0.05 (peek) / 0.45 (elevate)
    // bounce maps to dampingRatio via: dampingRatio = 1 - bounce
    private static let peekAnim: Animation = .interpolatingSpring(
        duration: 0.35, bounce: 0.05
    )
    private static let elevateAnim: Animation = .interpolatingSpring(
        duration: 0.35, bounce: 0.45
    )

    func mouseEntered() {
        log.write("VM: mouseEntered")
        collapseTask?.cancel()
        isMouseInside = true

        withAnimation(Self.elevateAnim) {
            isElevated = true
        }

        elevateTask?.cancel()
        elevateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, isMouseInside else { return }
            log.write("VM: quickPeeking")
            withAnimation(Self.peekAnim) {
                isQuickPeeking = true
            }
        }
    }

    func mouseExited() {
        log.write("VM: mouseExited")
        elevateTask?.cancel()
        isMouseInside = false

        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            withAnimation(Self.elevateAnim) {
                isQuickPeeking = false
                isElevated = false
            }
        }
    }
}
