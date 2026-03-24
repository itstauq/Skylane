import SwiftUI

@MainActor
@Observable
final class NotchViewModel {
    var isMouseInside = false
    var isElevated = false
    var isQuickPeeking = false
    var isExpanded = false
    var isViewPinned = false
    var isViewMenuOpen = false
    var isRenamingView = false
    var isEditingLayout = false
    var isShowingEditConfirmation = false
    var renameViewName = ""
    var renameViewFieldScreenRect: CGRect = .zero

    var notchWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    let viewManager = ViewManager()

    // Expanded panel dimensions
    var screenWidth: CGFloat = 0
    var expandedWidth: CGFloat { screenWidth * 0.54 }
    var expandedHeight: CGFloat { 300 }

    private let log = FileLog()
    private var elevateTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var editSessionLayoutsSnapshot: [UUID: ViewLayout]?
    private static let peekAnim: Animation = .interpolatingSpring(
        duration: 0.35, bounce: 0.05
    )
    private static let elevateAnim: Animation = .interpolatingSpring(
        duration: 0.35, bounce: 0.45
    )

    private var preventsAutoCollapse: Bool {
        isViewPinned || isViewMenuOpen || isRenamingView || isEditingLayout
    }

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

        guard !preventsAutoCollapse else { return }

        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, !preventsAutoCollapse, !isMouseInside else { return }
            collapse()
        }
    }

    func clicked() {
        log.write("VM: clicked, expanding")
        collapseTask?.cancel()
        withAnimation(Self.peekAnim) {
            isExpanded = true
            isElevated = true
            isQuickPeeking = true
        }
    }

    func collapse() {
        log.write("VM: collapsing")
        collapseTask?.cancel()
        withAnimation(Self.elevateAnim) {
            isExpanded = false
            isQuickPeeking = false
            isElevated = false
        }
        isViewMenuOpen = false
    }

    func togglePinnedView() {
        collapseTask?.cancel()

        if isViewPinned {
            log.write("VM: unpinning view")
            isViewPinned = false

            if !isMouseInside, !isViewMenuOpen, !isRenamingView {
                collapse()
            }
        } else {
            log.write("VM: pinning view")
            isViewPinned = true

            withAnimation(Self.peekAnim) {
                isExpanded = true
                isElevated = true
                isQuickPeeking = true
            }
        }
    }

    func toggleEditMode() {
        if isEditingLayout {
            attemptExitEditMode()
        } else {
            beginEditMode()
        }
    }

    func attemptExitEditMode() {
        guard isEditingLayout, !isShowingEditConfirmation else { return }

        if hasUnsavedLayoutChanges {
            presentEditConfirmation()
        } else {
            finishEditMode()
        }
    }

    func revertEditMode() {
        if let editSessionLayoutsSnapshot {
            viewManager.restoreLayouts(from: editSessionLayoutsSnapshot)
        }
        finishEditMode()
    }

    func saveEditMode() {
        finishEditMode()
    }

    func dismissEditConfirmation() {
        isShowingEditConfirmation = false
    }

    private func beginEditMode() {
        collapseTask?.cancel()
        editSessionLayoutsSnapshot = viewManager.layoutSnapshot()
        isEditingLayout = true
        withAnimation(Self.peekAnim) {
            isExpanded = true
            isElevated = true
            isQuickPeeking = true
        }
    }

    private var hasUnsavedLayoutChanges: Bool {
        guard let editSessionLayoutsSnapshot else { return false }
        return viewManager.layoutSnapshot() != editSessionLayoutsSnapshot
    }

    private func presentEditConfirmation() {
        isShowingEditConfirmation = true
    }

    private func finishEditMode() {
        editSessionLayoutsSnapshot = nil
        isShowingEditConfirmation = false
        isEditingLayout = false
    }
}
