import Foundation

private struct WidgetStorageKeyParams: Decodable {
    var key: String
}

private struct WidgetStorageSetParams: Decodable {
    var key: String
    var value: RuntimeJSONValue
}

enum WidgetStoragePreferenceKind {
    case text
    case password
    case checkbox
    case dropdown
    case camera
}

struct WidgetStoragePreferenceDefinition {
    var name: String
    var kind: WidgetStoragePreferenceKind
    var isRequired: Bool
    var defaultValue: RuntimeJSONValue?

    func isMissing(resolvedValue: RuntimeJSONValue?) -> Bool {
        guard let resolvedValue else { return true }

        switch kind {
        case .text, .password:
            return resolvedValue.stringValue?.isEmpty ?? true
        case .checkbox, .dropdown, .camera:
            return false
        }
    }
}

private let widgetPreferenceStorageKeyPrefix = "__widgetPreference__:"
private let widgetNotificationStorageKeyPrefix = "__widgetNotification__:"

final class WidgetStorageManager {
    private let fileManager: FileManager
    private let rootURL: URL
    private let storageEngine: WidgetStorageEngine
    private let encryptionEnabled: Bool
    private let log: (String) -> Void
    private let queue = DispatchQueue(label: "Skylane.WidgetStorage")

    init(
        fileManager: FileManager = .default,
        rootURL: URL = WidgetStorageManager.defaultRootURL(),
        secretProvider: WidgetStorageSecretProviding = WidgetStorageKeychain.shared,
        encryptionEnabled: Bool = Preferences.isWidgetStorageEncryptionEnabled,
        log: @escaping (String) -> Void = { _ in }
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
        self.encryptionEnabled = encryptionEnabled
        self.log = log
        self.storageEngine = WidgetStorageEngine(
            fileManager: fileManager,
            rootURL: rootURL,
            secretProvider: secretProvider,
            encryptionEnabled: encryptionEnabled,
            log: log
        )
    }

    func flushPendingWrites() {
        queue.sync {
            // Wait for previously enqueued writes to drain.
        }
    }

    func preferenceValues(widgetID: String, instanceID: String) -> [String: RuntimeJSONValue] {
        queue.sync {
            do {
                let values = try storageEngine.allItems(widgetID: widgetID, instanceID: instanceID)
                return Dictionary(
                    uniqueKeysWithValues: values.compactMap { key, value in
                        guard key.hasPrefix(widgetPreferenceStorageKeyPrefix) else { return nil }
                        return (String(key.dropFirst(widgetPreferenceStorageKeyPrefix.count)), value)
                    }
                )
            } catch {
                log("Widget preferences: failed to load snapshot for \(widgetID)/\(instanceID): \(error.localizedDescription)")
                return [:]
            }
        }
    }

    func setPreferenceValue(
        widgetID: String,
        instanceID: String,
        name: String,
        value: RuntimeJSONValue?
    ) throws {
        let storageKey = preferenceStorageKey(for: name)
        try queue.sync {
            if let value {
                try storageEngine.setItem(
                    widgetID: widgetID,
                    instanceID: instanceID,
                    key: storageKey,
                    value: value
                )
            } else {
                try storageEngine.removeItem(
                    widgetID: widgetID,
                    instanceID: instanceID,
                    key: storageKey
                )
            }
        }
    }

    func notificationsEnabled(
        widgetID: String,
        instanceID: String,
        defaultValue: Bool
    ) -> Bool {
        queue.sync {
            do {
                if let value = try storageEngine.item(
                    widgetID: widgetID,
                    instanceID: instanceID,
                    key: notificationStorageKey(for: "enabled")
                )?.boolValue {
                    return value
                }
            } catch {
                log("Widget notifications: failed to load state for \(widgetID)/\(instanceID): \(error.localizedDescription)")
            }

            return defaultValue
        }
    }

    func setNotificationsEnabled(
        widgetID: String,
        instanceID: String,
        enabled: Bool?
    ) throws {
        let storageKey = notificationStorageKey(for: "enabled")
        try queue.sync {
            if let enabled {
                try storageEngine.setItem(
                    widgetID: widgetID,
                    instanceID: instanceID,
                    key: storageKey,
                    value: .bool(enabled)
                )
            } else {
                try storageEngine.removeItem(
                    widgetID: widgetID,
                    instanceID: instanceID,
                    key: storageKey
                )
            }
        }
    }

    func resolvedPreferenceValues(
        widgetID: String,
        preferences: [WidgetStoragePreferenceDefinition],
        instanceID: String
    ) -> [String: RuntimeJSONValue] {
        let stored = preferenceValues(widgetID: widgetID, instanceID: instanceID)
        var resolved: [String: RuntimeJSONValue] = [:]

        for preference in preferences {
            if let value = stored[preference.name] {
                resolved[preference.name] = value
            } else if let defaultValue = preference.defaultValue {
                resolved[preference.name] = defaultValue
            }
        }

        return resolved
    }

    func missingRequiredPreferenceNames(
        widgetID: String,
        preferences: [WidgetStoragePreferenceDefinition],
        instanceID: String
    ) -> [String] {
        let resolved = resolvedPreferenceValues(
            widgetID: widgetID,
            preferences: preferences,
            instanceID: instanceID
        )
        return preferences.compactMap { preference in
            guard preference.isRequired else { return nil }
            return preference.isMissing(resolvedValue: resolved[preference.name]) ? preference.name : nil
        }
    }

    func handleRPC(
        widgetID: String,
        instanceID: String,
        method: String,
        params: RuntimeJSONValue?
    ) throws -> RuntimeJSONValue {
        switch method {
        case "localStorage.allItems":
            let snapshotResult: RuntimeJSONValue = queue.sync {
                do {
                    return RuntimeJSONValue.object(filteredLocalStorageItems(
                        try storageEngine.allItems(widgetID: widgetID, instanceID: instanceID)
                    ))
                } catch {
                    log("Widget storage: failed to load snapshot for \(widgetID)/\(instanceID): \(error.localizedDescription)")
                    return RuntimeJSONValue.null
                }
            }
            return try snapshotResult.mapAllItemsResult()

        case "localStorage.setItem":
            let setParams = try decode(params, as: WidgetStorageSetParams.self)
            try validateLocalStorageKey(setParams.key)
            try queue.sync {
                try self.storageEngine.setItem(
                    widgetID: widgetID,
                    instanceID: instanceID,
                    key: setParams.key,
                    value: setParams.value
                )
            }
            return .null

        case "localStorage.removeItem":
            let keyParams = try decode(params, as: WidgetStorageKeyParams.self)
            try validateLocalStorageKey(keyParams.key)
            try queue.sync {
                try self.storageEngine.removeItem(widgetID: widgetID, instanceID: instanceID, key: keyParams.key)
            }
            return .null

        default:
            throw RuntimeTransportRPCError(
                code: -32601,
                message: "Unsupported local storage RPC '\(method)'.",
                data: nil
            )
        }
    }

    private func decode<Result: Decodable>(_ value: RuntimeJSONValue?, as type: Result.Type) throws -> Result {
        let data = try JSONEncoder().encode(value ?? .null)
        return try JSONDecoder().decode(type, from: data)
    }

    private func preferenceStorageKey(for name: String) -> String {
        "\(widgetPreferenceStorageKeyPrefix)\(name)"
    }

    private func notificationStorageKey(for name: String) -> String {
        "\(widgetNotificationStorageKeyPrefix)\(name)"
    }

    private func filteredLocalStorageItems(_ items: [String: RuntimeJSONValue]) -> [String: RuntimeJSONValue] {
        items.filter { !isReservedHostStorageKey($0.key) }
    }

    private func validateLocalStorageKey(_ key: String) throws {
        guard !isReservedHostStorageKey(key) else {
            throw RuntimeTransportRPCError(
                code: -32602,
                message: "LocalStorage key '\(key)' uses a reserved Skylane host namespace.",
                data: nil
            )
        }
    }

    private func isReservedHostStorageKey(_ key: String) -> Bool {
        key.hasPrefix(widgetPreferenceStorageKeyPrefix) || key.hasPrefix(widgetNotificationStorageKeyPrefix)
    }

    private static func defaultRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Skylane", isDirectory: true)
            .appendingPathComponent("WidgetStorage", isDirectory: true)
    }
}

private extension RuntimeJSONValue {
    func mapAllItemsResult() throws -> RuntimeJSONValue {
        if case .null = self {
            throw RuntimeTransportRPCError(
                code: -32020,
                message: "Failed to load local storage snapshot.",
                data: nil
            )
        }

        return self
    }
}
