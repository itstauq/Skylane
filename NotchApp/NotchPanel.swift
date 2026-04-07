import AppKit
import SwiftUI

class NotchPanel: NSPanel {
    enum Kind {
        case blur
        case content
    }

    let kind: Kind

    init(contentRect: NSRect, level windowLevel: NSWindow.Level, kind: Kind) {
        self.kind = kind
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = windowLevel
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
        becomesKeyOnlyIfNeeded = true
    }

    var needsKeyInput = false

    override var canBecomeKey: Bool { needsKeyInput }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            handleRuntimeInputBlur(for: event)
        }

        super.sendEvent(event)
    }

    static var contentPanel: NotchPanel? {
        NSApp.windows
            .compactMap { $0 as? NotchPanel }
            .first { $0.kind == .content }
    }

    static var allPanels: [NotchPanel] {
        NSApp.windows.compactMap { $0 as? NotchPanel }
    }

    func setView<V: View>(_ view: V) {
        let hosting = FixedHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }

    func activateForKeyInput() {
        needsKeyInput = true
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func releaseKeyInput() {
        needsKeyInput = false
    }

    private func handleRuntimeInputBlur(for event: NSEvent) {
        guard needsKeyInput,
              let contentView,
              let editor = firstResponder as? NSTextView,
              let textField = editor.delegate as? NSTextField else { return }

        let locationInContent = contentView.convert(event.locationInWindow, from: nil)
        let hitView = contentView.hitTest(locationInContent)

        guard hitView?.isDescendant(of: textField) != true else { return }

        _ = makeFirstResponder(nil)
        releaseKeyInput()
    }
}

/// NSHostingView subclass that prevents window resize crashes
class FixedHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func invalidateIntrinsicContentSize() {
        // no-op: prevent triggering window constraint updates
    }
}
