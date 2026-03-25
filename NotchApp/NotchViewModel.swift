import Foundation
import SwiftUI

struct RuntimeEnvironmentPayload: Codable, Equatable {
    var widgetId: String
    var instanceId: String
    var viewId: String
    var span: Int
    var hostColumnCount: Int
    var isEditing: Bool
    var isDevelopment: Bool
}

struct RuntimeRenderNode: Codable, Equatable, Identifiable {
    var id: String
    var type: String
    var direction: String?
    var spacing: Double?
    var text: String?
    var title: String?
    var action: String?
    var children: [RuntimeRenderNode]

    init(
        id: String = UUID().uuidString,
        type: String,
        direction: String? = nil,
        spacing: Double? = nil,
        text: String? = nil,
        title: String? = nil,
        action: String? = nil,
        children: [RuntimeRenderNode] = []
    ) {
        self.id = id
        self.type = type
        self.direction = direction
        self.spacing = spacing
        self.text = text
        self.title = title
        self.action = action
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case direction
        case spacing
        case text
        case title
        case action
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try container.decode(String.self, forKey: .type)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        spacing = try container.decodeIfPresent(Double.self, forKey: .spacing)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        children = try container.decodeIfPresent([RuntimeRenderNode].self, forKey: .children) ?? []
    }
}

private struct RuntimeMountedWidget {
    var definition: WidgetDefinition
    var instanceID: UUID
    var viewID: UUID
    var span: Int
    var isEditing: Bool
    var isDevelopment: Bool

    var environment: RuntimeEnvironmentPayload {
        RuntimeEnvironmentPayload(
            widgetId: definition.id,
            instanceId: instanceID.uuidString,
            viewId: viewID.uuidString,
            span: span,
            hostColumnCount: ViewLayout.columnCount,
            isEditing: isEditing,
            isDevelopment: isDevelopment
        )
    }
}

private struct RuntimeRequestEnvelope: Codable {
    var requestID: String?
    var type: String
    var widgetID: String?
    var instanceID: String?
    var bundlePath: String?
    var actionID: String?
    var environment: RuntimeEnvironmentPayload?
}

private struct RuntimeResponseEnvelope: Codable {
    var requestID: String?
    var type: String
    var widgetID: String?
    var level: String?
    var message: String?
    var tree: RuntimeRenderNode?
}

@MainActor
@Observable
final class WidgetRuntimeController {
    var renderTreeByInstance: [UUID: RuntimeRenderNode] = [:]
    var errorByInstance: [UUID: String] = [:]
    var isAvailable = true

    private let log = FileLog()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var pending: [String: CheckedContinuation<RuntimeResponseEnvelope, Error>] = [:]
    private var loadedWidgetIDs: Set<String> = []
    private var mountedWidgets: [UUID: RuntimeMountedWidget] = [:]
    private var developmentWidgetIDs: Set<String> = []
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    func isMounted(instanceID: UUID) -> Bool {
        mountedWidgets[instanceID] != nil
    }

    func mount(widget definition: WidgetDefinition, instanceID: UUID, viewID: UUID, span: Int, isEditing: Bool) {
        mountedWidgets[instanceID] = RuntimeMountedWidget(
            definition: definition,
            instanceID: instanceID,
            viewID: viewID,
            span: span,
            isEditing: isEditing,
            isDevelopment: developmentWidgetIDs.contains(definition.id)
        )

        Task {
            await ensureLoaded(definition)
            await renderInstance(instanceID)
        }
    }

    func unmount(instanceID: UUID) {
        mountedWidgets.removeValue(forKey: instanceID)
        renderTreeByInstance.removeValue(forKey: instanceID)
        errorByInstance.removeValue(forKey: instanceID)
    }

    func update(instanceID: UUID, viewID: UUID, span: Int, isEditing: Bool) {
        guard var mounted = mountedWidgets[instanceID] else { return }
        mounted.viewID = viewID
        mounted.span = span
        mounted.isEditing = isEditing
        mounted.isDevelopment = developmentWidgetIDs.contains(mounted.definition.id)
        mountedWidgets[instanceID] = mounted

        Task {
            await renderInstance(instanceID)
        }
    }

    func triggerAction(_ actionID: String, for instanceID: UUID) {
        guard let mounted = mountedWidgets[instanceID] else { return }
        Task {
            await ensureLoaded(mounted.definition)
            do {
                _ = try await sendRequest(
                    RuntimeRequestEnvelope(
                        requestID: UUID().uuidString,
                        type: "action",
                        widgetID: mounted.definition.id,
                        instanceID: instanceID.uuidString,
                        bundlePath: nil,
                        actionID: actionID,
                        environment: mounted.environment
                    )
                )
                await renderInstance(instanceID)
            } catch {
                errorByInstance[instanceID] = error.localizedDescription
            }
        }
    }

    func renderTree(for instanceID: UUID) -> RuntimeRenderNode? {
        renderTreeByInstance[instanceID]
    }

    func error(for instanceID: UUID) -> String? {
        errorByInstance[instanceID]
    }

    func handleDevelopmentEvent(_ event: String, widgetID: String, info: String?) {
        switch event {
        case "start":
            Task {
                await setDevelopmentMode(true, for: widgetID)
            }
        case "build-success":
            Task {
                await setDevelopmentMode(true, for: widgetID)
                await handleBuildSuccess(widgetID: widgetID)
            }
        case "build-failure":
            Task {
                await setDevelopmentMode(true, for: widgetID)
            }
            let message = info?.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = (message?.isEmpty == false ? message : "Widget failed to build.")
            for mounted in mountedWidgets.values where mounted.definition.id == widgetID {
                errorByInstance[mounted.instanceID] = display
            }
        case "stop":
            Task {
                await setDevelopmentMode(false, for: widgetID)
            }
        default:
            break
        }
    }

    private func setDevelopmentMode(_ isDevelopment: Bool, for widgetID: String) async {
        if isDevelopment {
            developmentWidgetIDs.insert(widgetID)
        } else {
            developmentWidgetIDs.remove(widgetID)
        }

        let affectedInstances = mountedWidgets.values
            .filter { $0.definition.id == widgetID }
            .map(\.instanceID)

        for instanceID in affectedInstances {
            mountedWidgets[instanceID]?.isDevelopment = isDevelopment
            await renderInstance(instanceID)
        }
    }

    private func renderInstance(_ instanceID: UUID) async {
        guard let mounted = mountedWidgets[instanceID] else { return }
        await ensureLoaded(mounted.definition)

        do {
            let response = try await sendRequest(
                RuntimeRequestEnvelope(
                    requestID: UUID().uuidString,
                    type: "render",
                    widgetID: mounted.definition.id,
                    instanceID: instanceID.uuidString,
                    bundlePath: nil,
                    actionID: nil,
                    environment: mounted.environment
                )
            )

            if let tree = response.tree {
                renderTreeByInstance[instanceID] = tree
                errorByInstance.removeValue(forKey: instanceID)
            } else if let message = response.message {
                errorByInstance[instanceID] = message
            }
        } catch {
            errorByInstance[instanceID] = error.localizedDescription
        }
    }

    private func ensureLoaded(_ definition: WidgetDefinition) async {
        if !FileManager.default.fileExists(atPath: definition.bundleFileURL.path) {
            await rebuild(definition)
        }

        guard FileManager.default.fileExists(atPath: definition.bundleFileURL.path) else {
            isAvailable = false
            return
        }

        guard loadedWidgetIDs.contains(definition.id) == false else { return }

        do {
            _ = try await sendRequest(
                RuntimeRequestEnvelope(
                    requestID: UUID().uuidString,
                    type: "load",
                    widgetID: definition.id,
                    instanceID: nil,
                    bundlePath: definition.bundleFileURL.path,
                    actionID: nil,
                    environment: nil
                )
            )
            loadedWidgetIDs.insert(definition.id)
        } catch {
            isAvailable = false
            log.write("Widget runtime: load failed for \(definition.id): \(error.localizedDescription)")
        }
    }

    private func rebuild(_ definition: WidgetDefinition) async {
        let scriptURL = RepoPaths.developmentWidgetRuntimeRoot.appendingPathComponent("scripts/notch-widget")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else { return }

        let process = Process()
        process.executableURL = scriptURL
        process.arguments = ["build"]
        process.currentDirectoryURL = definition.package.directoryURL
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let status = try await waitForProcessExit(process)
            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            if !text.isEmpty {
                log.write("Widget build (\(definition.id)): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if status != 0 {
                log.write("Widget build failed for \(definition.id): exited with status \(status)")
            }
        } catch {
            log.write("Widget build failed for \(definition.id): \(error.localizedDescription)")
        }
    }

    private func waitForProcessExit(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            let finish: (Int32) -> Void = { status in
                lock.lock()
                defer { lock.unlock() }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: status)
            }

            process.terminationHandler = { process in
                finish(process.terminationStatus)
            }

            if !process.isRunning {
                finish(process.terminationStatus)
            }
        }
    }

    private func ensureProcess() async throws {
        if process?.isRunning == true, stdinHandle != nil {
            return
        }
        let newProcess = Process()

        if let bundledRuntimeRoot = RepoPaths.bundledWidgetRuntimeRoot,
           FileManager.default.fileExists(atPath: bundledRuntimeRoot.path) {
            let bundledNodeURL = bundledRuntimeRoot
                .appendingPathComponent("node", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("node")
            let bundledHelperURL = bundledRuntimeRoot
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("widget-helper.mjs")

            guard FileManager.default.fileExists(atPath: bundledNodeURL.path),
                  FileManager.default.fileExists(atPath: bundledHelperURL.path) else {
                throw NSError(
                    domain: "NotchWidgetRuntime",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Bundled widget runtime resources are incomplete."]
                )
            }

            newProcess.executableURL = bundledNodeURL
            newProcess.arguments = [bundledHelperURL.path]
            newProcess.currentDirectoryURL = bundledRuntimeRoot
        } else {
            let helperURL = RepoPaths.developmentWidgetRuntimeRoot.appendingPathComponent("scripts/notch-widget-helper")
            guard FileManager.default.fileExists(atPath: helperURL.path) else {
                throw NSError(domain: "NotchWidgetRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Widget helper script missing."])
            }

            newProcess.executableURL = helperURL
            newProcess.arguments = []
            newProcess.currentDirectoryURL = RepoPaths.developmentWidgetRuntimeRoot
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        newProcess.standardInput = stdinPipe
        newProcess.standardOutput = stdoutPipe
        newProcess.standardError = stderrPipe
        newProcess.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.handleProcessTermination(process)
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            Task { @MainActor [weak self] in
                self?.appendStdout(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            Task { @MainActor [weak self] in
                self?.appendStderr(data)
            }
        }

        try newProcess.run()
        process = newProcess
        stdinHandle = stdinPipe.fileHandleForWriting
        isAvailable = true
    }

    private func handleProcessTermination(_ terminatedProcess: Process) {
        guard process === terminatedProcess else { return }

        let status = terminatedProcess.terminationStatus
        let reason = terminatedProcess.terminationReason
        let description = "Widget runtime exited unexpectedly (reason: \(reason.rawValue), status: \(status))."

        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
        stdinHandle = nil
        process = nil
        loadedWidgetIDs.removeAll()
        isAvailable = false
        failPendingRequests(message: description)
    }

    private func failPendingRequests(message: String) {
        let error = NSError(
            domain: "NotchWidgetRuntime",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func appendStdout(_ data: Data) {
        stdoutBuffer.append(data)
        drain(buffer: &stdoutBuffer)
    }

    private func appendStderr(_ data: Data) {
        stderrBuffer.append(data)
        while let range = stderrBuffer.range(of: Data([0x0A])) {
            let lineData = stderrBuffer.subdata(in: 0..<range.lowerBound)
            stderrBuffer.removeSubrange(0...range.lowerBound)
            let line = String(decoding: lineData, as: UTF8.self)
            if !line.isEmpty {
                log.write("Widget helper stderr: \(line)")
            }
        }
    }

    private func drain(buffer: inout Data) {
        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0...range.lowerBound)
            guard !lineData.isEmpty else { continue }

            do {
                let envelope = try jsonDecoder.decode(RuntimeResponseEnvelope.self, from: lineData)
                handle(envelope)
            } catch {
                let line = String(decoding: lineData, as: UTF8.self)
                log.write("Widget helper decode error: \(line)")
            }
        }
    }

    private func handle(_ envelope: RuntimeResponseEnvelope) {
        if envelope.type == "log" {
            let level = envelope.level ?? "info"
            let widgetID = envelope.widgetID ?? "unknown"
            log.write("Widget \(widgetID) [\(level)]: \(envelope.message ?? "")")
            return
        }

        guard let requestID = envelope.requestID,
              let continuation = pending.removeValue(forKey: requestID) else { return }
        continuation.resume(returning: envelope)
    }

    private func sendRequest(_ request: RuntimeRequestEnvelope) async throws -> RuntimeResponseEnvelope {
        try await ensureProcess()
        guard let requestID = request.requestID else {
            throw NSError(domain: "NotchWidgetRuntime", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing request id."])
        }
        guard let stdinHandle else {
            throw NSError(domain: "NotchWidgetRuntime", code: 3, userInfo: [NSLocalizedDescriptionKey: "Widget runtime stdin unavailable."])
        }

        let data = try jsonEncoder.encode(request)
        var line = data
        line.append(0x0A)

        return try await withCheckedThrowingContinuation { continuation in
            pending[requestID] = continuation

            do {
                try stdinHandle.write(contentsOf: line)
            } catch {
                pending.removeValue(forKey: requestID)
                continuation.resume(throwing: error)
            }
        }
    }

    private func handleBuildSuccess(widgetID: String) async {
        loadedWidgetIDs.remove(widgetID)

        let refreshedDefinitions = WidgetCatalog.discover(log: log)
        let matchingDefinition = refreshedDefinitions.first(where: { $0.id == widgetID })

        for (instanceID, mounted) in mountedWidgets where mounted.definition.id == widgetID {
            if let matchingDefinition {
                mountedWidgets[instanceID]?.definition = matchingDefinition
            }
        }

        let affectedInstances = mountedWidgets.values
            .filter { $0.definition.id == widgetID }
            .map(\.instanceID)

        guard let matchingDefinition else {
            for instanceID in affectedInstances {
                errorByInstance[instanceID] = "This widget is currently unavailable."
            }
            return
        }

        guard FileManager.default.fileExists(atPath: matchingDefinition.bundleFileURL.path) else {
            for instanceID in affectedInstances {
                errorByInstance[instanceID] = "This widget is currently unavailable."
            }
            return
        }

        for instanceID in affectedInstances {
            await renderInstance(instanceID)
        }
    }
}

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
    let widgetRuntime = WidgetRuntimeController()

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

    init() {}

    func refreshWidgetDefinitions() {
        viewManager.reloadWidgetDefinitions()
    }

    func handleDevelopmentEvent(widgetID: String, event: String, info: String?) {
        refreshWidgetDefinitions()
        widgetRuntime.handleDevelopmentEvent(event, widgetID: widgetID, info: info)
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
        refreshWidgetDefinitions()
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
        refreshWidgetDefinitions()
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
