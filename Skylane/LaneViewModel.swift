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
    var isVisible: Bool
}

struct RuntimeRenderNode: Codable, Equatable, Identifiable {
    var id: String
    var type: String
    var direction: String?
    var spacing: Double?
    var role: String?
    var tone: String?
    var text: String?
    var title: String?
    var action: String?
    var symbol: String?
    var payload: RuntimeActionPayload?
    var checked: Bool?
    var disabled: Bool?
    var lineClamp: Int?
    var strikethrough: Bool?
    var value: String?
    var placeholder: String?
    var changeAction: String?
    var submitAction: String?
    var leadingAccessory: RuntimeNodeBox?
    var trailingAccessory: RuntimeNodeBox?
    var children: [RuntimeRenderNode]

    init(
        id: String = "",
        type: String,
        direction: String? = nil,
        spacing: Double? = nil,
        role: String? = nil,
        tone: String? = nil,
        text: String? = nil,
        title: String? = nil,
        action: String? = nil,
        symbol: String? = nil,
        payload: RuntimeActionPayload? = nil,
        checked: Bool? = nil,
        disabled: Bool? = nil,
        lineClamp: Int? = nil,
        strikethrough: Bool? = nil,
        value: String? = nil,
        placeholder: String? = nil,
        changeAction: String? = nil,
        submitAction: String? = nil,
        leadingAccessory: RuntimeNodeBox? = nil,
        trailingAccessory: RuntimeNodeBox? = nil,
        children: [RuntimeRenderNode] = []
    ) {
        self.id = id
        self.type = type
        self.direction = direction
        self.spacing = spacing
        self.role = role
        self.tone = tone
        self.text = text
        self.title = title
        self.action = action
        self.symbol = symbol
        self.payload = payload
        self.checked = checked
        self.disabled = disabled
        self.lineClamp = lineClamp
        self.strikethrough = strikethrough
        self.value = value
        self.placeholder = placeholder
        self.changeAction = changeAction
        self.submitAction = submitAction
        self.leadingAccessory = leadingAccessory
        self.trailingAccessory = trailingAccessory
        self.children = children
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case direction
        case spacing
        case role
        case tone
        case text
        case title
        case action
        case symbol
        case payload
        case checked
        case disabled
        case lineClamp
        case strikethrough
        case value
        case placeholder
        case changeAction
        case submitAction
        case leadingAccessory
        case trailingAccessory
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        type = try container.decode(String.self, forKey: .type)
        direction = try container.decodeIfPresent(String.self, forKey: .direction)
        spacing = try container.decodeIfPresent(Double.self, forKey: .spacing)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        tone = try container.decodeIfPresent(String.self, forKey: .tone)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        action = try container.decodeIfPresent(String.self, forKey: .action)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        payload = try container.decodeIfPresent(RuntimeActionPayload.self, forKey: .payload)
        checked = try container.decodeIfPresent(Bool.self, forKey: .checked)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        lineClamp = try container.decodeIfPresent(Int.self, forKey: .lineClamp)
        strikethrough = try container.decodeIfPresent(Bool.self, forKey: .strikethrough)
        value = try container.decodeIfPresent(String.self, forKey: .value)
        placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
        changeAction = try container.decodeIfPresent(String.self, forKey: .changeAction)
        submitAction = try container.decodeIfPresent(String.self, forKey: .submitAction)
        leadingAccessory = try container.decodeIfPresent(RuntimeNodeBox.self, forKey: .leadingAccessory)
        trailingAccessory = try container.decodeIfPresent(RuntimeNodeBox.self, forKey: .trailingAccessory)
        children = try container.decodeIfPresent([RuntimeRenderNode].self, forKey: .children) ?? []
    }

    func normalizedForRuntime(path: String = "root") -> RuntimeRenderNode {
        let resolvedID = id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? path : id
        let normalizedLeadingAccessory = leadingAccessory.map {
            RuntimeNodeBox(node: $0.node.normalizedForRuntime(path: "\(resolvedID).leadingAccessory"))
        }
        let normalizedTrailingAccessory = trailingAccessory.map {
            RuntimeNodeBox(node: $0.node.normalizedForRuntime(path: "\(resolvedID).trailingAccessory"))
        }
        let normalizedChildren = children.enumerated().map { index, child in
            child.normalizedForRuntime(path: "\(resolvedID).children.\(index)")
        }

        return RuntimeRenderNode(
            id: resolvedID,
            type: type,
            direction: direction,
            spacing: spacing,
            role: role,
            tone: tone,
            text: text,
            title: title,
            action: action,
            symbol: symbol,
            payload: payload,
            checked: checked,
            disabled: disabled,
            lineClamp: lineClamp,
            strikethrough: strikethrough,
            value: value,
            placeholder: placeholder,
            changeAction: changeAction,
            submitAction: submitAction,
            leadingAccessory: normalizedLeadingAccessory,
            trailingAccessory: normalizedTrailingAccessory,
            children: normalizedChildren
        )
    }
}

struct RuntimeActionPayload: Codable, Equatable {
    var value: String?
    var id: String?
}

final class RuntimeNodeBox: Codable, Equatable {
    var node: RuntimeRenderNode

    init(node: RuntimeRenderNode) {
        self.node = node
    }

    static func == (lhs: RuntimeNodeBox, rhs: RuntimeNodeBox) -> Bool {
        lhs.node == rhs.node
    }
}

private struct RuntimeMountedWidget {
    var definition: WidgetDefinition
    var instanceID: UUID
    var viewID: UUID
    var span: Int
    var isEditing: Bool
    var isDevelopment: Bool
    var isVisible: Bool
    var sessionID: String?

    var environment: RuntimeEnvironmentPayload {
        RuntimeEnvironmentPayload(
            widgetId: definition.id,
            instanceId: instanceID.uuidString,
            viewId: viewID.uuidString,
            span: span,
            hostColumnCount: ViewLayout.columnCount,
            isEditing: isEditing,
            isDevelopment: isDevelopment,
            isVisible: isVisible
        )
    }
}

private struct RuntimeLegacyLoadParams: Encodable {
    var widgetID: String?
    var bundlePath: String?
}

private struct RuntimeMountParams: Encodable {
    var widgetId: String
    var instanceId: String
    var bundlePath: String
    var props: RuntimeMountProps
}

private struct RuntimeMountProps: Encodable {
    var environment: RuntimeEnvironmentPayload
    var preferences: [String: RuntimeJSONValue]
    var theme: WidgetResolvedTheme
}

private struct RuntimeUpdatePropsParams: Encodable {
    var instanceId: String
    var sessionId: String
    var props: RuntimeMountProps
}

private struct RuntimeHostEventParams: Encodable {
    var instanceId: String
    var sessionId: String
    var name: String
    var payload: RuntimeJSONValue
}

private struct RuntimeMountResult: Decodable {
    var sessionId: String
}

private struct RuntimeTerminateParams: Encodable {
    var instanceId: String
    var sessionId: String
}

private struct RuntimeCallbackParams: Encodable {
    var instanceId: String
    var sessionId: String
    var callbackId: String
    var payload: RuntimeJSONValue
}

private struct RuntimeRequestFullTreeParams: Encodable {
    var instanceId: String
    var sessionId: String
}

private struct RuntimeLegacyRenderParams: Encodable {
    var widgetID: String?
    var instanceID: String?
    var environment: RuntimeEnvironmentPayload?
}

private struct RuntimeLegacyActionParams: Encodable {
    var widgetID: String?
    var instanceID: String?
    var actionID: String?
    var payload: RuntimeActionPayload?
    var environment: RuntimeEnvironmentPayload?
}

private struct RuntimeLegacyRenderResult: Decodable {
    var tree: RuntimeRenderNode
}

private struct RuntimeLogNotificationParams: Decodable {
    var widgetID: String?
    var instanceId: String?
    var level: String?
    var message: String?
}

struct WidgetPreferencesDidChangePayload {
    var instanceID: UUID
}

extension Notification.Name {
    static let widgetPreferencesDidChange = Notification.Name("widgetPreferencesDidChange")
}

@MainActor
@Observable
final class WidgetRuntimeController {
    var renderTreeByInstance: [UUID: RenderNodeV2] = [:]
    var errorByInstance: [UUID: String] = [:]
    var isAvailable = true

    private let log = FileLog()
    private let transport = RuntimeTransport()
    private let sessionManager = WidgetSessionManager()
    private let storageManager = WidgetStorageManager(log: { FileLog().write($0) })
    @ObservationIgnored private var hostAPI: WidgetHostAPI! = nil
    private var mountedWidgets: [UUID: RuntimeMountedWidget] = [:]
    private var developmentWidgetIDs: Set<String> = []
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    init() {
        let mediaService = WidgetHostMediaService(
            onStateChange: { [weak self] state in
                self?.broadcastHostEvent(named: "media.state", payload: state)
            },
            log: { [weak self] message in
                self?.log.write(message)
            }
        )
        let audioService = WidgetHostAudioService(
            onStateChange: { [weak self] instanceID, state in
                self?.broadcastHostEvent(
                    named: "audio.state",
                    payload: state,
                    instanceIDs: [instanceID]
                )
            },
            log: { [weak self] message in
                self?.log.write(message)
            }
        )
        let eventsService = WidgetHostEventsService(
            onStateChange: { [weak self] in
                self?.broadcastHostEvent(
                    named: "events.changed",
                    payload: ["revisionMs": Date().timeIntervalSince1970 * 1000]
                )
            },
            log: { [weak self] message in
                self?.log.write(message)
            }
        )
        hostAPI = WidgetHostAPI(
            sessionManager: sessionManager,
            storage: storageManager,
            network: WidgetHostNetworkService(),
            media: mediaService,
            audio: audioService,
            events: eventsService,
            notifications: WidgetNotificationService.shared,
            resolveWidgetID: { [weak self] instanceID in
                self?.mountedWidgets[instanceID]?.definition.id
            },
            resolveWidgetDefinition: { [weak self] instanceID in
                self?.mountedWidgets[instanceID]?.definition
            },
            log: { [weak self] message in
                self?.log.write(message)
            }
        )
        transport.notificationHandler = { [weak self] notification in
            self?.handle(notification)
        }
        transport.requestHandler = { [weak self] request in
            guard let self else {
                throw RuntimeTransportRPCError(
                    code: -32000,
                    message: "Widget runtime host is unavailable.",
                    data: nil
                )
            }

            return try await self.handle(request)
        }
        transport.stderrHandler = { [weak self] line in
            self?.log.write("Widget helper stderr: \(line)")
        }
        transport.terminationHandler = { [weak self] description in
            self?.handleProcessTermination(description: description)
        }
    }

    func isMounted(instanceID: UUID) -> Bool {
        mountedWidgets[instanceID] != nil
    }

    func flushStorageWrites() {
        storageManager.flushPendingWrites()
    }

    func resolvedPreferences(for instanceID: UUID) -> [String: RuntimeJSONValue] {
        guard let mounted = mountedWidgets[instanceID] else { return [:] }
        return storageManager.resolvedPreferenceValues(
            widgetID: mounted.definition.id,
            preferences: storagePreferenceDefinitions(from: mounted.definition.preferences),
            instanceID: instanceID.uuidString
        )
    }

    func missingRequiredPreferenceNamesAsync(for definition: WidgetDefinition, instanceID: UUID) async -> [String] {
        await storageManager.missingRequiredPreferenceNamesAsync(
            widgetID: definition.id,
            preferences: storagePreferenceDefinitions(from: definition.preferences),
            instanceID: instanceID.uuidString
        )
    }

    func missingRequiredPreferenceNames(for instanceID: UUID) -> [String] {
        guard let mounted = mountedWidgets[instanceID] else { return [] }
        return missingRequiredPreferenceNames(for: mounted.definition, instanceID: instanceID)
    }

    func missingRequiredPreferenceNames(for definition: WidgetDefinition, instanceID: UUID) -> [String] {
        return storageManager.missingRequiredPreferenceNames(
            widgetID: definition.id,
            preferences: storagePreferenceDefinitions(from: definition.preferences),
            instanceID: instanceID.uuidString
        )
    }

    func preferencesDidChange(instanceID: UUID) {
        Task {
            await syncMountedWorkerProps(instanceID)
        }
    }

    func mount(widget definition: WidgetDefinition, instanceID: UUID, viewID: UUID, span: Int, isEditing: Bool, isVisible: Bool) {
        mountedWidgets[instanceID] = RuntimeMountedWidget(
            definition: definition,
            instanceID: instanceID,
            viewID: viewID,
            span: span,
            isEditing: isEditing,
            isDevelopment: developmentWidgetIDs.contains(definition.id),
            isVisible: isVisible,
            sessionID: nil
        )
        errorByInstance.removeValue(forKey: instanceID)
        sessionManager.beginMount(instanceID: instanceID)

        Task {
            await mountInstance(instanceID)
        }
    }

    func unmount(instanceID: UUID) {
        let mounted = mountedWidgets.removeValue(forKey: instanceID)
        let sessionID = sessionManager.knownSessionID(for: instanceID)
        sessionManager.remove(instanceID: instanceID)
        renderTreeByInstance.removeValue(forKey: instanceID)
        errorByInstance.removeValue(forKey: instanceID)
        WidgetImagePipeline.clearCache(for: instanceID)
        hostAPI.removeInstance(instanceID)

        guard let mounted, let sessionID else { return }

        Task {
            do {
                _ = try await sendRequest(
                    "terminate",
                    params: RuntimeTerminateParams(
                        instanceId: instanceID.uuidString,
                        sessionId: sessionID
                    )
                )
            } catch {
                log.write("Widget runtime: terminate failed for \(mounted.definition.id): \(error.localizedDescription)")
            }
        }
    }

    func reconcileMountedInstances(with layoutsByViewID: [UUID: ViewLayout]) {
        let activeInstanceIDs = Set(
            layoutsByViewID.values.flatMap { layout in
                layout.widgets.map(\.id)
            }
        )
        let staleInstanceIDs = mountedWidgets.keys.filter { !activeInstanceIDs.contains($0) }
        for instanceID in staleInstanceIDs {
            unmount(instanceID: instanceID)
        }
    }

    func update(instanceID: UUID, viewID: UUID, span: Int, isEditing: Bool, isVisible: Bool) {
        guard var mounted = mountedWidgets[instanceID] else { return }
        mounted.viewID = viewID
        mounted.span = span
        mounted.isEditing = isEditing
        mounted.isDevelopment = developmentWidgetIDs.contains(mounted.definition.id)
        mounted.isVisible = isVisible
        mountedWidgets[instanceID] = mounted

        Task {
            await syncMountedWorkerProps(instanceID)
        }
    }

    func triggerAction(_ actionID: String, payload: RuntimeActionPayload? = nil, for instanceID: UUID) {
        _ = actionID
        _ = payload
        _ = instanceID
    }

    func triggerCallback(
        prop: String = "onPress",
        for instanceID: UUID,
        at path: [Int],
        payload: RuntimeJSONValue = .object([:])
    ) {
        guard let root = renderTreeByInstance[instanceID],
              let node = node(at: path, in: root),
              let callbackID = node.string(prop),
              sessionManager.knownSessionID(for: instanceID) != nil else {
            return
        }

        triggerCallback(callbackID: callbackID, for: instanceID, payload: payload)
    }

    func triggerCallback(
        callbackID: String,
        for instanceID: UUID,
        payload: RuntimeJSONValue = .object([:])
    ) {
        guard let sessionID = sessionManager.knownSessionID(for: instanceID) else {
            return
        }

        do {
            try transport.sendNotification(
                "callback",
                params: RuntimeCallbackParams(
                    instanceId: instanceID.uuidString,
                    sessionId: sessionID,
                    callbackId: callbackID,
                    payload: payload
                ),
                configuration: try processConfiguration()
            )
        } catch {
            log.write("Widget runtime: callback failed for \(instanceID.uuidString): \(error.localizedDescription)")
        }
    }

    func renderTree(for instanceID: UUID) -> RenderNodeV2? {
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
            await syncMountedWorkerProps(instanceID)
        }
    }

    private func syncMountedWorkerProps(_ instanceID: UUID) async {
        guard let mounted = mountedWidgets[instanceID] else { return }

        guard let sessionID = sessionManager.knownSessionID(for: instanceID) else {
            await ensureMountedWorker(instanceID)
            return
        }

        do {
            let props = await mountProps(for: mounted)
            try transport.sendNotification(
                "updateProps",
                params: RuntimeUpdatePropsParams(
                    instanceId: instanceID.uuidString,
                    sessionId: sessionID,
                    props: props
                ),
                configuration: try processConfiguration()
            )
            isAvailable = true
        } catch {
            log.write("Widget runtime: updateProps failed for \(instanceID.uuidString): \(error.localizedDescription)")
        }
    }

    private func ensureMountedWorker(_ instanceID: UUID) async {
        guard mountedWidgets[instanceID] != nil else { return }
        guard mountedWidgets[instanceID]?.sessionID == nil else { return }
        guard !sessionManager.hasPendingMount(for: instanceID) else { return }

        sessionManager.beginMount(instanceID: instanceID)
        await mountInstance(instanceID)
    }

    private func mountInstance(_ instanceID: UUID) async {
        guard let mounted = mountedWidgets[instanceID] else { return }
        guard await ensureBundleAvailable(mounted.definition) else {
            errorByInstance[instanceID] = "This widget is currently unavailable."
            sessionManager.remove(instanceID: instanceID)
            renderTreeByInstance.removeValue(forKey: instanceID)
            return
        }

        storageManager.flushPendingWrites()

        do {
            let props = await mountProps(for: mounted)
            let response = try await sendRequest(
                "mount",
                params: RuntimeMountParams(
                    widgetId: mounted.definition.id,
                    instanceId: instanceID.uuidString,
                    bundlePath: mounted.definition.bundleFileURL.path,
                    props: props
                )
            )
            let result = try decode(response, as: RuntimeMountResult.self)

            guard mountedWidgets[instanceID] != nil else {
                sessionManager.remove(instanceID: instanceID)
                renderTreeByInstance.removeValue(forKey: instanceID)
                _ = try? await sendRequest(
                    "terminate",
                    params: RuntimeTerminateParams(
                        instanceId: instanceID.uuidString,
                        sessionId: result.sessionId
                    )
                )
                return
            }

            try sessionManager.activate(instanceID: instanceID, sessionId: result.sessionId)
            mountedWidgets[instanceID]?.sessionID = result.sessionId
            errorByInstance.removeValue(forKey: instanceID)
            isAvailable = true

            await syncMountedWorkerProps(instanceID)
        } catch {
            sessionManager.remove(instanceID: instanceID)
            renderTreeByInstance.removeValue(forKey: instanceID)
            errorByInstance[instanceID] = error.localizedDescription
        }
    }

    private func ensureBundleAvailable(_ definition: WidgetDefinition) async -> Bool {
        if !FileManager.default.fileExists(atPath: definition.bundleFileURL.path) {
            await rebuild(definition)
        }

        guard FileManager.default.fileExists(atPath: definition.bundleFileURL.path) else {
            isAvailable = false
            return false
        }

        return true
    }

    private func restartInstance(_ instanceID: UUID) async {
        guard mountedWidgets[instanceID] != nil else { return }

        let sessionID = sessionManager.knownSessionID(for: instanceID)
        sessionManager.remove(instanceID: instanceID)
        mountedWidgets[instanceID]?.sessionID = nil
        WidgetImagePipeline.clearCache(for: instanceID)

        if let sessionID {
            do {
                _ = try await sendRequest(
                    "terminate",
                    params: RuntimeTerminateParams(
                        instanceId: instanceID.uuidString,
                        sessionId: sessionID
                    )
                )
            } catch {
                log.write("Widget runtime: terminate failed during restart for \(instanceID.uuidString): \(error.localizedDescription)")
            }
        }

        sessionManager.beginMount(instanceID: instanceID)
        await mountInstance(instanceID)
    }

    private func rebuild(_ definition: WidgetDefinition) async {
        let launcherURL = RepoPaths.developmentWidgetRuntimeRoot.appendingPathComponent("runtime-launcher")
        guard FileManager.default.fileExists(atPath: launcherURL.path) else { return }

        let process = Process()
        process.executableURL = launcherURL
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

    func shutdown() {
        transport.sendBestEffortNotificationIfRunning("shutdown")
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

    private func processConfiguration() throws -> RuntimeTransportProcessConfiguration {
        if let bundledRuntimeRoot = RepoPaths.bundledWidgetRuntimeRoot,
           FileManager.default.fileExists(atPath: bundledRuntimeRoot.path) {
            let bundledNodeURL = bundledRuntimeRoot
                .appendingPathComponent("node", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("node")
            let bundledRuntimeURL = bundledRuntimeRoot
                .appendingPathComponent("runtime-v2.mjs")

            guard FileManager.default.fileExists(atPath: bundledNodeURL.path),
                  FileManager.default.fileExists(atPath: bundledRuntimeURL.path) else {
                throw NSError(
                    domain: "SkylaneWidgetRuntime",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Bundled widget runtime resources are incomplete."]
                )
            }

            return RuntimeTransportProcessConfiguration(
                executableURL: bundledNodeURL,
                arguments: [bundledRuntimeURL.path],
                currentDirectoryURL: bundledRuntimeRoot
            )
        }

        let launcherURL = RepoPaths.developmentWidgetRuntimeRoot.appendingPathComponent("runtime-launcher")
        guard FileManager.default.fileExists(atPath: launcherURL.path) else {
            throw NSError(domain: "SkylaneWidgetRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Widget runtime launcher missing."])
        }

        return RuntimeTransportProcessConfiguration(
            executableURL: launcherURL,
            arguments: ["v2"],
            currentDirectoryURL: RepoPaths.developmentWidgetRuntimeRoot
        )
    }

    private func mountProps(for mounted: RuntimeMountedWidget) async -> RuntimeMountProps {
        let preferences = await storageManager.resolvedPreferenceValuesAsync(
            widgetID: mounted.definition.id,
            preferences: storagePreferenceDefinitions(from: mounted.definition.preferences),
            instanceID: mounted.instanceID.uuidString
        )

        return RuntimeMountProps(
            environment: mounted.environment,
            preferences: preferences,
            theme: mounted.definition.resolvedTheme
        )
    }

    private func storagePreferenceDefinitions(from preferences: [WidgetPreferenceDefinition]) -> [WidgetStoragePreferenceDefinition] {
        preferences.map {
            WidgetStoragePreferenceDefinition(
                name: $0.name,
                kind: storagePreferenceKind(for: $0.type),
                isRequired: $0.isRequired,
                defaultValue: $0.defaultValue
            )
        }
    }

    private func storagePreferenceKind(for type: WidgetPreferenceType) -> WidgetStoragePreferenceKind {
        switch type {
        case .textfield:
            return .text
        case .password:
            return .password
        case .checkbox:
            return .checkbox
        case .dropdown:
            return .dropdown
        case .camera:
            return .camera
        }
    }

    private func handleProcessTermination(description: String) {
        log.write(description)
        isAvailable = false
        WidgetImagePipeline.clearCaches(for: Array(mountedWidgets.keys))
        sessionManager.reset()
        renderTreeByInstance.removeAll()
        for instanceID in mountedWidgets.keys {
            mountedWidgets[instanceID]?.sessionID = nil
        }
    }

    private func handle(_ notification: RuntimeTransportNotification) {
        if notification.method == "render" {
            guard let params = try? decode(notification.params, as: WidgetRenderNotificationParams.self),
                  let instanceID = UUID(uuidString: params.instanceId) else {
                return
            }

            switch sessionManager.acceptRender(
                instanceID: instanceID,
                sessionId: params.sessionId,
                kind: params.kind,
                renderRevision: params.renderRevision,
                data: params.data
            ) {
            case .ignored:
                return
            case .applied(let tree):
                renderTreeByInstance[instanceID] = tree
                errorByInstance.removeValue(forKey: instanceID)
                return
            case .requestFullTree(let reason):
                requestFullTree(for: instanceID, sessionID: params.sessionId, reason: reason)
                return
            }
        }

        if notification.method == "error" {
            guard let params = try? decode(notification.params, as: WidgetErrorNotificationParams.self),
                  let instanceID = UUID(uuidString: params.instanceId) else {
                return
            }

            if let sessionID = sessionManager.knownSessionID(for: instanceID),
               sessionID != params.sessionId {
                return
            }

            renderTreeByInstance.removeValue(forKey: instanceID)
            errorByInstance[instanceID] = params.error.message
            return
        }

        if notification.method == "log" {
            guard let params = try? decode(notification.params, as: RuntimeLogNotificationParams.self) else {
                return
            }
            let level = params.level ?? "info"
            let subject = params.widgetID ?? params.instanceId ?? "unknown"
            log.write("Widget \(subject) [\(level)]: \(params.message ?? "")")
        }
    }

    private func sendRequest<Params: Encodable>(_ method: String, params: Params? = nil) async throws -> RuntimeJSONValue? {
        let configuration = try processConfiguration()
        let response = try await transport.sendRequest(method, params: params, configuration: configuration)
        isAvailable = true
        return response
    }

    private func decode<Result: Decodable>(_ value: RuntimeJSONValue?, as type: Result.Type) throws -> Result {
        try (value ?? .null).decode(as: type, using: jsonDecoder)
    }

    private func encodeRuntimeJSONValue<Value: Encodable>(_ value: Value) throws -> RuntimeJSONValue {
        let data = try jsonEncoder.encode(value)
        return try jsonDecoder.decode(RuntimeJSONValue.self, from: data)
    }

    private func requestFullTree(for instanceID: UUID, sessionID: String, reason: String) {
        log.write("Widget runtime: requesting full tree for \(instanceID.uuidString): \(reason)")

        do {
            try transport.sendNotification(
                "requestFullTree",
                params: RuntimeRequestFullTreeParams(
                    instanceId: instanceID.uuidString,
                    sessionId: sessionID
                ),
                configuration: try processConfiguration()
            )
        } catch {
            log.write("Widget runtime: requestFullTree failed for \(instanceID.uuidString): \(error.localizedDescription)")
        }
    }

    private func broadcastHostEvent<Value: Encodable>(
        named name: String,
        payload: Value,
        instanceIDs: [UUID]? = nil
    ) {
        let encodedPayload: RuntimeJSONValue
        do {
            encodedPayload = try encodeRuntimeJSONValue(payload)
        } catch {
            log.write("Widget runtime: failed to encode host event \(name): \(error.localizedDescription)")
            return
        }

        let targetInstanceIDs = instanceIDs ?? Array(mountedWidgets.keys)
        for instanceID in targetInstanceIDs {
            guard let sessionID = sessionManager.knownSessionID(for: instanceID) else {
                continue
            }

            transport.sendBestEffortNotificationIfRunning(
                "hostEvent",
                params: RuntimeHostEventParams(
                    instanceId: instanceID.uuidString,
                    sessionId: sessionID,
                    name: name,
                    payload: encodedPayload
                )
            )
        }
    }

    private func node(at path: [Int], in root: RenderNodeV2) -> RenderNodeV2? {
        var current = root
        for index in path {
            guard current.children.indices.contains(index) else {
                return nil
            }
            current = current.children[index]
        }
        return current
    }

    private func handle(_ request: RuntimeTransportRequest) async throws -> RuntimeJSONValue? {
        try await hostAPI.handle(request)
    }

    private func handleBuildSuccess(widgetID: String) async {
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

        WidgetImagePipeline.clearCaches(for: affectedInstances)

        for instanceID in affectedInstances {
            await restartInstance(instanceID)
        }
    }
}

@MainActor
@Observable
final class LaneViewModel {
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

    var laneWidth: CGFloat = 0
    var laneHeight: CGFloat = 0
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

    func syncWidgetRuntimeLayouts() {
        widgetRuntime.reconcileMountedInstances(with: viewManager.layoutSnapshot())
    }

    func refreshWidgetDefinitions() {
        viewManager.reloadWidgetDefinitions()
    }

    func isWidgetVisible(_ instanceID: UUID) -> Bool {
        guard isExpanded,
              let selectedView = viewManager.selectedView,
              let widget = viewManager.widget(id: instanceID, in: selectedView) else {
            return false
        }

        return viewManager.definition(for: widget) != nil
    }

    func revealWidget(_ instanceID: UUID) -> Bool {
        refreshWidgetDefinitions()

        guard let targetView = viewManager.views.first(where: { view in
            viewManager.layout(for: view).widgets.contains(where: { $0.id == instanceID })
        }) else {
            withAnimation(Self.peekAnim) {
                isExpanded = true
                isElevated = true
                isQuickPeeking = true
            }
            return false
        }

        viewManager.select(targetView)
        collapseTask?.cancel()
        withAnimation(Self.peekAnim) {
            isExpanded = true
            isElevated = true
            isQuickPeeking = true
        }
        return true
    }

    func handleDevelopmentEvent(widgetID: String, event: String, info: String?) {
        refreshWidgetDefinitions()
        widgetRuntime.handleDevelopmentEvent(event, widgetID: widgetID, info: info)
    }

    func flushStorageWrites() {
        widgetRuntime.flushStorageWrites()
    }

    func mouseEntered() {
        log.write("VM: mouseEntered")
        collapseTask?.cancel()
        restoreDefaultViewIfNeeded()
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
        restoreDefaultViewIfNeeded()
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

    private func restoreDefaultViewIfNeeded() {
        guard !Preferences.rememberLastView,
              let firstView = viewManager.views.first,
              viewManager.selectedViewID != firstView.id else { return }
        viewManager.selectedViewID = firstView.id
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
        viewManager.persistCurrentState()
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
        LanePanel.contentPanel?.activateForKeyInput()
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
        LanePanel.contentPanel?.releaseKeyInput()
    }
}
