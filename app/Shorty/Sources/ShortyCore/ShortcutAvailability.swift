import Foundation

extension CanonicalShortcut.Category {
    public var availabilitySortOrder: Int {
        switch self {
        case .navigation:
            return 0
        case .search:
            return 1
        case .editing:
            return 2
        case .tabs:
            return 3
        case .windows:
            return 4
        case .media:
            return 5
        case .system:
            return 6
        }
    }
}

public enum AvailableShortcutActionKind: String, Codable, Equatable {
    case passthrough
    case keyRemap
    case menuInvoke
    case axAction

    public var label: String {
        switch self {
        case .passthrough:
            return "Native"
        case .keyRemap:
            return "Sends keys"
        case .menuInvoke:
            return "Menu"
        case .axAction:
            return "Action"
        }
    }
}

public struct AvailableShortcut: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let defaultKeys: KeyCombo
    public let category: CanonicalShortcut.Category
    public let actionKind: AvailableShortcutActionKind
    public let actionDescription: String
    public let nativeKeys: KeyCombo?
    public let menuTitle: String?
    public let axAction: String?
    public let adapterSource: Adapter.Source

    public init(
        id: String,
        name: String,
        defaultKeys: KeyCombo,
        category: CanonicalShortcut.Category,
        actionKind: AvailableShortcutActionKind,
        actionDescription: String,
        nativeKeys: KeyCombo? = nil,
        menuTitle: String? = nil,
        axAction: String? = nil,
        adapterSource: Adapter.Source
    ) {
        self.id = id
        self.name = name
        self.defaultKeys = defaultKeys
        self.category = category
        self.actionKind = actionKind
        self.actionDescription = actionDescription
        self.nativeKeys = nativeKeys
        self.menuTitle = menuTitle
        self.axAction = axAction
        self.adapterSource = adapterSource
    }
}

public struct ShortcutAvailability: Codable, Equatable {
    public enum State: String, Codable {
        case noActiveApp
        case noAdapter
        case available
    }

    public let state: State
    public let appIdentifier: String?
    public let appDisplayName: String
    public let adapterIdentifier: String?
    public let adapterName: String?
    public let adapterSource: Adapter.Source?
    public let shortcuts: [AvailableShortcut]

    public init(
        state: State,
        appIdentifier: String?,
        appDisplayName: String,
        adapterIdentifier: String? = nil,
        adapterName: String? = nil,
        adapterSource: Adapter.Source? = nil,
        shortcuts: [AvailableShortcut] = []
    ) {
        self.state = state
        self.appIdentifier = appIdentifier
        self.appDisplayName = appDisplayName
        self.adapterIdentifier = adapterIdentifier
        self.adapterName = adapterName
        self.adapterSource = adapterSource
        self.shortcuts = shortcuts
    }

    public var coverageTitle: String {
        switch state {
        case .noActiveApp:
            return "No active app"
        case .noAdapter:
            return "Pass through"
        case .available:
            return "\(shortcuts.count) available"
        }
    }

    public var coverageDetail: String {
        switch state {
        case .noActiveApp:
            return "Shorty will show shortcuts after an app is active."
        case .noAdapter:
            return "Shorty does not have shortcuts for \(appDisplayName) yet."
        case .available:
            return "Shorty is ready for \(adapterName ?? appDisplayName)."
        }
    }
}

public struct EngineDisplayStatus: Codable, Equatable {
    public let title: String
    public let detail: String
    public let isHealthy: Bool
    public let requiresPermission: Bool
    public let isWaitingForPermission: Bool

    public init(
        title: String,
        detail: String,
        isHealthy: Bool,
        requiresPermission: Bool,
        isWaitingForPermission: Bool
    ) {
        self.title = title
        self.detail = detail
        self.isHealthy = isHealthy
        self.requiresPermission = requiresPermission
        self.isWaitingForPermission = isWaitingForPermission
    }

    public static func make(
        status: EngineStatus,
        permissionState: PermissionState,
        eventTapEnabled: Bool,
        isWaitingForPermission: Bool
    ) -> EngineDisplayStatus {
        if permissionState != .granted || status == .permissionRequired {
            return EngineDisplayStatus(
                title: isWaitingForPermission
                    ? "Waiting for Accessibility access"
                    : "Needs Accessibility access",
                detail: isWaitingForPermission
                    ? "Approve Shorty in System Settings. This will update automatically."
                    : "Allow Shorty in Accessibility settings to translate shortcuts.",
                isHealthy: false,
                requiresPermission: true,
                isWaitingForPermission: isWaitingForPermission
            )
        }

        switch status {
        case .running where eventTapEnabled:
            return EngineDisplayStatus(
                title: "Ready",
                detail: "Shorty is translating shortcuts for supported apps.",
                isHealthy: true,
                requiresPermission: false,
                isWaitingForPermission: false
            )
        case .disabled, .running:
            return EngineDisplayStatus(
                title: "Paused",
                detail: "Shorty is passing shortcuts through unchanged.",
                isHealthy: true,
                requiresPermission: false,
                isWaitingForPermission: false
            )
        case .starting:
            return EngineDisplayStatus(
                title: "Starting",
                detail: "Preparing shortcut translation.",
                isHealthy: false,
                requiresPermission: false,
                isWaitingForPermission: false
            )
        case .failed(let message):
            return EngineDisplayStatus(
                title: "Needs attention",
                detail: message,
                isHealthy: false,
                requiresPermission: false,
                isWaitingForPermission: false
            )
        case .stopped:
            return EngineDisplayStatus(
                title: "Stopped",
                detail: "Start Shorty to translate shortcuts.",
                isHealthy: false,
                requiresPermission: false,
                isWaitingForPermission: false
            )
        case .permissionRequired:
            return EngineDisplayStatus(
                title: "Needs Accessibility access",
                detail: "Allow Shorty in Accessibility settings to translate shortcuts.",
                isHealthy: false,
                requiresPermission: true,
                isWaitingForPermission: isWaitingForPermission
            )
        }
    }
}
