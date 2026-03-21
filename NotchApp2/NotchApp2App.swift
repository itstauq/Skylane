import SwiftUI

@main
struct NotchApp2App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let logger = FileLog()
    private var eventMonitor: Any?
    private var notchRect: CGRect = .zero
    private var notchPanel: NotchPanel?
    private var blurPanel: NotchPanel?
    private let vm = NotchViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.write("App launched")
        setupStatusBar()
        setupNotch()
        startMouseMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
        logger.write("App exiting")
    }

    private func setupNotch() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            logger.write("No notch screen found")
            return
        }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let w = screen.frame.width - left - right
        let h = screen.safeAreaInsets.top
        notchRect = CGRect(
            x: screen.frame.midX - w / 2,
            y: screen.frame.maxY - h,
            width: w, height: h
        )
        vm.notchWidth = w
        vm.notchHeight = h
        logger.write("Notch rect: \(notchRect)")

        // Panel sizing — room for grow effect + blur bleed
        let panelW = w + 60
        let panelH = h + 40
        let panelRect = NSRect(
            x: screen.frame.midX - panelW / 2,
            y: screen.frame.maxY - panelH,
            width: panelW, height: panelH
        )

        // Back panel: progressive blur glow (behind the notch)
        let blur = NotchPanel(
            contentRect: panelRect,
            level: .init(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        )
        blur.setView(NotchBlurView(vm: vm))
        blur.alphaValue = 0
        blur.orderFrontRegardless()
        blurPanel = blur

        // Front panel: the notch shape itself
        let panel = NotchPanel(
            contentRect: panelRect,
            level: .init(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        )
        panel.setView(NotchContentView(vm: vm))
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        notchPanel = panel
    }

    private func startMouseMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            let inside = mouse.x >= notchRect.minX && mouse.x <= notchRect.maxX
                && mouse.y >= notchRect.minY && mouse.y <= notchRect.maxY
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if inside != vm.isMouseInside {
                    if inside {
                        notchPanel?.alphaValue = 1
                        blurPanel?.alphaValue = 1
                        vm.mouseEntered()
                        logger.write("Mouse entered notch")
                    } else {
                        vm.mouseExited()
                        logger.write("Mouse exited notch")
                        // Hide panels after collapse animation completes
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .milliseconds(500))
                            guard let self, !self.vm.isMouseInside else { return }
                            self.notchPanel?.alphaValue = 0
                            self.blurPanel?.alphaValue = 0
                        }
                    }
                }
            }
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchApp2")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

struct FileLog {
    private let url = URL(fileURLWithPath: "/Users/tauquir/Projects/NotchApp2/notchapp2.log")

    func write(_ message: String) {
        let line = "[\(Self.fmt.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: url.path, contents: data)
        }
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
