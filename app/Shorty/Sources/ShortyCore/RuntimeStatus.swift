import Foundation
import OSLog

/// Runtime toggles that keep release behavior explicit and testable.
public struct EngineConfiguration: Equatable {
    /// When true, Shorty may auto-generate menu adapters when an unknown app
    /// becomes active. Release builds keep this off to avoid silent disk writes.
    public let autoGenerateMenuAdapters: Bool

    /// When true, the browser bridge reports domains even when Shorty does not
    /// ship a web-app adapter for them. Release builds keep this off by default.
    public let reportAllBrowserDomains: Bool

    /// Maximum time the UI waits for an adapter preview before reporting a
    /// timeout. The underlying Accessibility query is best-effort.
    public let adapterGenerationTimeout: TimeInterval
    public let startsEventTap: Bool
    public let startsBrowserBridge: Bool

    public init(
        autoGenerateMenuAdapters: Bool = false,
        reportAllBrowserDomains: Bool = false,
        adapterGenerationTimeout: TimeInterval = 3,
        startsEventTap: Bool = true,
        startsBrowserBridge: Bool = true
    ) {
        self.autoGenerateMenuAdapters = autoGenerateMenuAdapters
        self.reportAllBrowserDomains = reportAllBrowserDomains
        self.adapterGenerationTimeout = adapterGenerationTimeout
        self.startsEventTap = startsEventTap
        self.startsBrowserBridge = startsBrowserBridge
    }

    public static let releaseDefault = EngineConfiguration()
    public static let appStoreCandidate = EngineConfiguration(
        startsEventTap: false,
        startsBrowserBridge: false
    )
}

public enum PermissionState: String, Codable, Equatable {
    case unknown
    case granted
    case notGranted

    public var isGranted: Bool {
        self == .granted
    }
}

public enum EngineStatus: Equatable {
    case stopped
    case starting
    case running
    case disabled
    case permissionRequired
    case failed(String)

    public var title: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting"
        case .running:
            return "Shorty is active"
        case .disabled:
            return "Shorty is disabled"
        case .permissionRequired:
            return "Accessibility permission needed"
        case .failed:
            return "Shorty needs attention"
        }
    }

    public var detail: String {
        switch self {
        case .stopped:
            return "Start Shorty to translate shortcuts for supported apps."
        case .starting:
            return "Preparing the keyboard shortcut engine."
        case .running:
            return "Supported app shortcuts are being translated."
        case .disabled:
            return "Turn Shorty back on when you want shortcut translation."
        case .permissionRequired:
            return "macOS requires Accessibility permission before Shorty can listen for keyboard shortcuts."
        case .failed(let message):
            return message
        }
    }

    public var isHealthy: Bool {
        switch self {
        case .running, .disabled:
            true
        case .stopped, .starting, .permissionRequired, .failed:
            false
        }
    }
}

public enum BrowserBridgeStatus: Equatable {
    case stopped
    case listening(String)
    case connected(String)
    case failed(String)

    public var title: String {
        switch self {
        case .stopped:
            return "Browser bridge stopped"
        case .listening:
            return "Browser bridge ready"
        case .connected(let domain):
            return "Browser bridge connected to \(domain)"
        case .failed:
            return "Browser bridge needs attention"
        }
    }

    public var detail: String {
        switch self {
        case .stopped:
            return "Web-app adapters are optional and native app shortcuts still work."
        case .listening(let path):
            return "Listening at \(path)."
        case .connected(let domain):
            return "Using the web adapter for \(domain)."
        case .failed(let message):
            return message
        }
    }
}

public enum AdapterValidationError: Error, Equatable, CustomStringConvertible {
    case fileTooLarge(Int)
    case emptyAppIdentifier
    case invalidAppIdentifier(String)
    case emptyAppName
    case noMappings(String)
    case tooManyMappings(String)
    case duplicateCanonicalID(String)
    case unknownCanonicalID(String)
    case missingNativeKeys(String)
    case unexpectedNativeKeys(String)
    case missingMenuTitle(String)
    case unexpectedMenuTitle(String)
    case missingAXAction(String)
    case unexpectedAXAction(String)
    case invalidContext(String)

    public var description: String {
        switch self {
        case .fileTooLarge(let size):
            "adapter file is too large (\(size) bytes)"
        case .emptyAppIdentifier:
            "adapter app identifier is empty"
        case .invalidAppIdentifier(let identifier):
            "adapter app identifier is invalid: \(identifier)"
        case .emptyAppName:
            "adapter app name is empty"
        case .noMappings(let identifier):
            "\(identifier) has no mappings"
        case .tooManyMappings(let identifier):
            "\(identifier) has too many mappings"
        case .duplicateCanonicalID(let canonicalID):
            "duplicate mapping for \(canonicalID)"
        case .unknownCanonicalID(let canonicalID):
            "unknown canonical shortcut \(canonicalID)"
        case .missingNativeKeys(let canonicalID):
            "\(canonicalID) is missing native keys"
        case .unexpectedNativeKeys(let canonicalID):
            "\(canonicalID) has native keys for a non-remap method"
        case .missingMenuTitle(let canonicalID):
            "\(canonicalID) is missing a menu title"
        case .unexpectedMenuTitle(let canonicalID):
            "\(canonicalID) has a menu title for a non-menu method"
        case .missingAXAction(let canonicalID):
            "\(canonicalID) is missing an AX action"
        case .unexpectedAXAction(let canonicalID):
            "\(canonicalID) has an AX action for a non-AX method"
        case .invalidContext(let canonicalID):
            "\(canonicalID) has an invalid context filter"
        }
    }
}

public enum ShortyLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.peyton.shorty"

    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let adapterRegistry = Logger(subsystem: subsystem, category: "adapter-registry")
    public static let eventTap = Logger(subsystem: subsystem, category: "event-tap")
    public static let browserBridge = Logger(subsystem: subsystem, category: "browser-bridge")
}
