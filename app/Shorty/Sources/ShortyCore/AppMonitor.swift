import AppKit
import Combine

/// Tracks which application is frontmost, publishing changes reactively.
///
/// AppMonitor observes `NSWorkspace.didActivateApplicationNotification`
/// and caches the current bundle identifier. The EventTapManager reads
/// this on every keystroke (via the fast `currentAppID` property) rather
/// than querying NSWorkspace each time.
public final class AppMonitor: ObservableObject {
    public struct Snapshot: Equatable {
        public let currentBundleID: String?
        public let currentAppName: String?
        public let currentPID: pid_t
        public let webAppDomain: String?
        public let browserContextSource: BrowserContextSource
        public let browserContextUpdatedAt: Date?
        public let effectiveAppID: String?

        public init(
            currentBundleID: String?,
            currentAppName: String?,
            currentPID: pid_t,
            webAppDomain: String?,
            browserContextSource: BrowserContextSource,
            browserContextUpdatedAt: Date?,
            effectiveAppID: String?
        ) {
            self.currentBundleID = currentBundleID
            self.currentAppName = currentAppName
            self.currentPID = currentPID
            self.webAppDomain = webAppDomain
            self.browserContextSource = browserContextSource
            self.browserContextUpdatedAt = browserContextUpdatedAt
            self.effectiveAppID = effectiveAppID
        }
    }

    public static let browserContextExpirationInterval: TimeInterval = 30

    /// The bundle identifier of the frontmost app, or nil if unknown.
    @Published public private(set) var currentBundleID: String?

    /// The localized name of the frontmost app.
    @Published public private(set) var currentAppName: String?

    /// The PID of the frontmost app (needed for AXUIElement in Phase 2).
    @Published public private(set) var currentPID: pid_t = 0

    /// For web apps: the domain reported by the browser extension (Phase 3).
    /// When set, this overrides bundle-ID-based adapter lookup.
    @Published public var webAppDomain: String?

    /// Describes which browser integration last supplied `webAppDomain`.
    @Published public private(set) var browserContextSource: BrowserContextSource = .none

    /// The effective identifier used for adapter lookup.
    /// Returns "web:<domain>" if a browser extension has reported a web app,
    /// otherwise the native bundle ID.
    public var effectiveAppID: String? {
        snapshot().effectiveAppID
    }

    @Published public private(set) var browserContextUpdatedAt: Date?

    private var cancellable: AnyCancellable?
    private let stateLock = NSRecursiveLock()

    public init() {
        // Seed with current frontmost app
        if let app = NSWorkspace.shared.frontmostApplication {
            updateActiveApplication(
                bundleIdentifier: app.bundleIdentifier,
                localizedName: app.localizedName,
                processIdentifier: app.processIdentifier
            )
        }

        // Observe future changes
        cancellable = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { notification -> NSRunningApplication? in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.updateActiveApplication(
                    bundleIdentifier: app.bundleIdentifier,
                    localizedName: app.localizedName,
                    processIdentifier: app.processIdentifier
                )
            }
    }

    public func updateActiveApplication(
        bundleIdentifier: String?,
        localizedName: String?,
        processIdentifier: pid_t
    ) {
        stateLock.lock()
        let previousBundleID = currentBundleID
        currentBundleID = bundleIdentifier
        currentAppName = localizedName
        currentPID = processIdentifier
        stateLock.unlock()

        if previousBundleID != bundleIdentifier || !isBrowser(bundleIdentifier) {
            clearBrowserContext()
        }
    }

    public func updateBrowserContext(
        domain: String,
        source: BrowserContextSource
    ) {
        stateLock.lock()
        webAppDomain = DomainNormalizer.normalizedDomain(for: domain)
        browserContextSource = source
        browserContextUpdatedAt = Date()
        stateLock.unlock()
    }

    public func clearBrowserContext(source: BrowserContextSource? = nil) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard source == nil || source == browserContextSource else { return }
        webAppDomain = nil
        browserContextSource = .none
        browserContextUpdatedAt = nil
    }

    @discardableResult
    public func expireStaleBrowserContext(now: Date = Date()) -> Bool {
        stateLock.lock()
        let updatedAt = browserContextUpdatedAt
        let hasContext = webAppDomain != nil
        let isStale = updatedAt.map {
            now.timeIntervalSince($0) > Self.browserContextExpirationInterval
        } ?? false
        stateLock.unlock()

        guard hasContext, isStale else { return false }
        clearBrowserContext()
        return true
    }

    public func snapshot(now: Date = Date()) -> Snapshot {
        stateLock.lock()
        defer { stateLock.unlock() }

        let domain: String?
        let source: BrowserContextSource
        if let updatedAt = browserContextUpdatedAt,
           now.timeIntervalSince(updatedAt) <= Self.browserContextExpirationInterval {
            domain = webAppDomain
            source = browserContextSource
        } else {
            domain = nil
            source = .none
        }

        let effectiveID: String?
        if let domain, isBrowser(currentBundleID) {
            effectiveID = DomainNormalizer.adapterIdentifier(for: domain)
        } else {
            effectiveID = currentBundleID
        }

        return Snapshot(
            currentBundleID: currentBundleID,
            currentAppName: currentAppName,
            currentPID: currentPID,
            webAppDomain: domain,
            browserContextSource: source,
            browserContextUpdatedAt: domain == nil ? nil : browserContextUpdatedAt,
            effectiveAppID: effectiveID
        )
    }

    // MARK: - Browser detection

    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",  // Arc
        "org.mozilla.firefox",
        "org.mozilla.nightly",
        "com.operasoftware.Opera"
    ]

    private func isBrowser(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return Self.browserBundleIDs.contains(id)
    }
}
