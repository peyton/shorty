import Foundation

public struct UserShortcutProfile: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var shortcuts: [CanonicalShortcut]
    public var updatedAt: Date

    public init(
        id: String = "default",
        name: String = "Default",
        shortcuts: [CanonicalShortcut] = CanonicalShortcut.defaults,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.shortcuts = shortcuts
        self.updatedAt = updatedAt
    }

    public static let releaseDefault = UserShortcutProfile()

    public func conflicts() -> [ShortcutConflict] {
        ShortcutConflict.detect(in: shortcuts)
    }
}

public struct ShortcutConflict: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable {
        case duplicateKeyCombo
        case contextSensitiveUnguarded
        case macOSReserved
    }

    public let id: String
    public let kind: Kind
    public let shortcutIDs: [String]
    public let keyCombo: KeyCombo?
    public let message: String

    public init(
        kind: Kind,
        shortcutIDs: [String],
        keyCombo: KeyCombo?,
        message: String
    ) {
        self.kind = kind
        self.shortcutIDs = shortcutIDs
        self.keyCombo = keyCombo
        self.message = message
        self.id = "\(kind.rawValue):\(shortcutIDs.joined(separator: ",")):\(keyCombo?.description ?? "none")"
    }

    public static func detect(in shortcuts: [CanonicalShortcut]) -> [ShortcutConflict] {
        var conflicts: [ShortcutConflict] = []
        let groupedByCombo = Dictionary(grouping: shortcuts, by: \.defaultKeys)
        for (combo, duplicates) in groupedByCombo where duplicates.count > 1 {
            conflicts.append(
                ShortcutConflict(
                    kind: .duplicateKeyCombo,
                    shortcutIDs: duplicates.map(\.id).sorted(),
                    keyCombo: combo,
                    message: "\(combo.description) is assigned to more than one shortcut."
                )
            )
        }

        let contextSensitiveIDs: Set<String> = ["submit_field", "newline_in_field"]
        for shortcut in shortcuts where contextSensitiveIDs.contains(shortcut.id) {
            conflicts.append(
                ShortcutConflict(
                    kind: .contextSensitiveUnguarded,
                    shortcutIDs: [shortcut.id],
                    keyCombo: shortcut.defaultKeys,
                    message: "\(shortcut.name) can change text-entry behavior and should be guarded by app context or explicit user approval."
                )
            )
        }

        return conflicts.sorted { $0.id < $1.id }
    }
}

public struct KeyboardLayoutDescriptor: Codable, Equatable {
    public let inputSourceID: String
    public let localizedName: String
    public let keyboardType: String

    public init(
        inputSourceID: String = "unknown",
        localizedName: String = "Unknown keyboard layout",
        keyboardType: String = "unknown"
    ) {
        self.inputSourceID = inputSourceID
        self.localizedName = localizedName
        self.keyboardType = keyboardType
    }
}

public struct ShortcutCaptureResult: Codable, Equatable {
    public enum State: String, Codable {
        case idle
        case recording
        case captured
        case cancelled
        case invalid
    }

    public let state: State
    public let keyCombo: KeyCombo?
    public let layout: KeyboardLayoutDescriptor
    public let message: String

    public init(
        state: State,
        keyCombo: KeyCombo? = nil,
        layout: KeyboardLayoutDescriptor = KeyboardLayoutDescriptor(),
        message: String
    ) {
        self.state = state
        self.keyCombo = keyCombo
        self.layout = layout
        self.message = message
    }
}

public struct AdapterReview: Codable, Equatable, Identifiable {
    public let id: String
    public let adapterIdentifier: String
    public let confidence: Double
    public let reasons: [String]
    public let warnings: [String]

    public init(
        adapterIdentifier: String,
        confidence: Double,
        reasons: [String] = [],
        warnings: [String] = []
    ) {
        self.adapterIdentifier = adapterIdentifier
        self.confidence = confidence
        self.reasons = reasons
        self.warnings = warnings
        self.id = adapterIdentifier
    }
}

public struct AdapterRevision: Codable, Equatable, Identifiable {
    public let id: UUID
    public let adapterIdentifier: String
    public let createdAt: Date
    public let summary: String
    public let adapter: Adapter

    public init(
        id: UUID = UUID(),
        adapterIdentifier: String,
        createdAt: Date = Date(),
        summary: String,
        adapter: Adapter
    ) {
        self.id = id
        self.adapterIdentifier = adapterIdentifier
        self.createdAt = createdAt
        self.summary = summary
        self.adapter = adapter
    }
}

public enum BrowserContextSource: String, Codable, Equatable {
    case none
    case chromeBridge
    case safariExtension

    public var title: String {
        switch self {
        case .none:
            return "No browser context"
        case .chromeBridge:
            return "Chrome-family bridge"
        case .safariExtension:
            return "Safari extension"
        }
    }
}

public enum BridgeBrowserTarget: String, Codable, CaseIterable, Identifiable {
    case chrome
    case chromeCanary
    case chromium
    case brave
    case edge
    case vivaldi
    case safari

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chrome:
            return "Google Chrome"
        case .chromeCanary:
            return "Chrome Canary"
        case .chromium:
            return "Chromium"
        case .brave:
            return "Brave"
        case .edge:
            return "Microsoft Edge"
        case .vivaldi:
            return "Vivaldi"
        case .safari:
            return "Safari"
        }
    }
}

public struct BridgeInstallStatus: Codable, Equatable, Identifiable {
    public enum State: String, Codable {
        case notInstalled
        case installed
        case needsAttention
        case unsupported
    }

    public let id: String
    public let browser: BridgeBrowserTarget
    public let state: State
    public let manifestPath: String?
    public let helperPath: String?
    public let detail: String

    public init(
        browser: BridgeBrowserTarget,
        state: State,
        manifestPath: String? = nil,
        helperPath: String? = nil,
        detail: String
    ) {
        self.browser = browser
        self.state = state
        self.manifestPath = manifestPath
        self.helperPath = helperPath
        self.detail = detail
        self.id = browser.id
    }
}

public struct SafariExtensionStatus: Codable, Equatable {
    public static let developerIDBundleIdentifier = "app.peyton.shorty.SafariWebExtension"
    public static let appStoreBundleIdentifier = "app.peyton.shorty.appstore.SafariWebExtension"

    public enum State: String, Codable {
        case unknown
        case bundled
        case enabled
        case disabled
        case missing
        case needsAttention
    }

    public let state: State
    public let bundleIdentifier: String
    public let lastMessageAt: Date?
    public let lastDomain: String?
    public let detail: String

    public static func bundleIdentifier(
        forAppBundleIdentifier appBundleIdentifier: String?
    ) -> String {
        if appBundleIdentifier == "app.peyton.shorty.appstore" {
            return appStoreBundleIdentifier
        }
        return developerIDBundleIdentifier
    }

    public init(
        state: State = .unknown,
        bundleIdentifier: String? = nil,
        lastMessageAt: Date? = nil,
        lastDomain: String? = nil,
        detail: String = "Safari extension status has not been checked."
    ) {
        self.state = state
        self.bundleIdentifier = bundleIdentifier ?? Self.bundleIdentifier(
            forAppBundleIdentifier: Bundle.main.bundleIdentifier
        )
        self.lastMessageAt = lastMessageAt
        self.lastDomain = lastDomain
        self.detail = detail
    }

    public var title: String {
        switch state {
        case .unknown:
            return "Safari extension not checked"
        case .bundled:
            return "Safari extension bundled"
        case .enabled:
            return "Safari extension enabled"
        case .disabled:
            return "Safari extension disabled"
        case .missing:
            return "Safari extension missing"
        case .needsAttention:
            return "Safari extension needs attention"
        }
    }
}

public struct RuntimeDiagnosticSnapshot: Codable, Equatable {
    public let createdAt: Date
    public let engineStatus: String
    public let permissionState: PermissionState
    public let currentAppName: String?
    public let currentBundleID: String?
    public let effectiveAppID: String?
    public let browserContextSource: BrowserContextSource
    public let webDomain: String?
    public let bridgeStatus: String
    public let safariExtensionStatus: SafariExtensionStatus
    public let eventsIntercepted: Int
    public let eventsRemapped: Int
    public let adapterValidationMessages: [String]

    public init(
        createdAt: Date = Date(),
        engineStatus: String,
        permissionState: PermissionState,
        currentAppName: String?,
        currentBundleID: String?,
        effectiveAppID: String?,
        browserContextSource: BrowserContextSource,
        webDomain: String?,
        bridgeStatus: String,
        safariExtensionStatus: SafariExtensionStatus,
        eventsIntercepted: Int,
        eventsRemapped: Int,
        adapterValidationMessages: [String]
    ) {
        self.createdAt = createdAt
        self.engineStatus = engineStatus
        self.permissionState = permissionState
        self.currentAppName = currentAppName
        self.currentBundleID = currentBundleID
        self.effectiveAppID = effectiveAppID
        self.browserContextSource = browserContextSource
        self.webDomain = webDomain
        self.bridgeStatus = bridgeStatus
        self.safariExtensionStatus = safariExtensionStatus
        self.eventsIntercepted = eventsIntercepted
        self.eventsRemapped = eventsRemapped
        self.adapterValidationMessages = adapterValidationMessages
    }
}

public struct SupportBundle: Codable, Equatable {
    public let createdAt: Date
    public let diagnostics: RuntimeDiagnosticSnapshot
    public let shortcutProfile: UserShortcutProfile
    public let adapters: [String]
    public let notes: [String]

    public init(
        createdAt: Date = Date(),
        diagnostics: RuntimeDiagnosticSnapshot,
        shortcutProfile: UserShortcutProfile,
        adapters: [String],
        notes: [String] = []
    ) {
        self.createdAt = createdAt
        self.diagnostics = diagnostics
        self.shortcutProfile = shortcutProfile
        self.adapters = adapters
        self.notes = notes
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public struct ReleaseVerificationResult: Codable, Equatable {
    public enum State: String, Codable {
        case passed
        case failed
        case skipped
    }

    public let check: String
    public let state: State
    public let detail: String

    public init(check: String, state: State, detail: String) {
        self.check = check
        self.state = state
        self.detail = detail
    }
}

public struct UpdateStatus: Codable, Equatable {
    public enum State: String, Codable {
        case notConfigured
        case idle
        case checking
        case updateAvailable
        case upToDate
        case failed
    }

    public let state: State
    public let lastCheckedAt: Date?
    public let automaticChecksEnabled: Bool
    public let detail: String

    public init(
        state: State = .notConfigured,
        lastCheckedAt: Date? = nil,
        automaticChecksEnabled: Bool = false,
        detail: String = "Direct-download updates are not configured in this build."
    ) {
        self.state = state
        self.lastCheckedAt = lastCheckedAt
        self.automaticChecksEnabled = automaticChecksEnabled
        self.detail = detail
    }

    public var title: String {
        switch state {
        case .notConfigured:
            return "Updates not configured"
        case .idle:
            return "Updates ready"
        case .checking:
            return "Checking for updates"
        case .updateAvailable:
            return "Update available"
        case .upToDate:
            return "Shorty is up to date"
        case .failed:
            return "Update check failed"
        }
    }
}
