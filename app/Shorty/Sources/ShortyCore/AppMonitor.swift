import AppKit
import Combine

/// Tracks which application is frontmost, publishing changes reactively.
///
/// AppMonitor observes `NSWorkspace.didActivateApplicationNotification`
/// and caches the current bundle identifier. The EventTapManager reads
/// this on every keystroke (via the fast `currentAppID` property) rather
/// than querying NSWorkspace each time.
public final class AppMonitor: ObservableObject {
    public struct ActiveApplicationSnapshot: Equatable {
        public let bundleIdentifier: String?
        public let localizedName: String?
        public let processIdentifier: pid_t
        public let isTerminated: Bool

        public init(
            bundleIdentifier: String?,
            localizedName: String?,
            processIdentifier: pid_t,
            isTerminated: Bool = false
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.localizedName = localizedName
            self.processIdentifier = processIdentifier
            self.isTerminated = isTerminated
        }
    }

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

    private var cancellables = Set<AnyCancellable>()
    private let stateLock = NSRecursiveLock()
    private let ignoredBundleIdentifiers: Set<String>

    public init(
        ignoredBundleIdentifiers: Set<String>? = nil
    ) {
        self.ignoredBundleIdentifiers = ignoredBundleIdentifiers
            ?? AppMonitor.defaultIgnoredBundleIdentifiers()

        // Seed with current frontmost app
        refreshActiveApplication()

        // Observe future changes
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { notification -> NSRunningApplication? in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.updateActiveApplication(Self.snapshot(for: app))
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { notification -> NSRunningApplication? in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.activeApplicationDidTerminate(Self.snapshot(for: app))
            }
            .store(in: &cancellables)
    }

    @discardableResult
    public func activeApplicationDidTerminate(
        _ application: ActiveApplicationSnapshot
    ) -> Bool {
        stateLock.lock()
        let isCurrentApplication = currentPID == application.processIdentifier &&
            currentBundleID == application.bundleIdentifier
        guard isCurrentApplication else {
            stateLock.unlock()
            return false
        }

        currentBundleID = nil
        currentAppName = nil
        currentPID = 0
        stateLock.unlock()

        clearBrowserContext()
        return true
    }

    @discardableResult
    public func refreshActiveApplication() -> Bool {
        refreshActiveApplication(
            frontmostApplication: NSWorkspace.shared.frontmostApplication.map(Self.snapshot)
        )
    }

    @discardableResult
    public func refreshActiveApplication(
        frontmostApplication: ActiveApplicationSnapshot?
    ) -> Bool {
        guard let frontmostApplication else { return false }
        return updateActiveApplication(frontmostApplication)
    }

    @discardableResult
    public func updateActiveApplication(
        bundleIdentifier: String?,
        localizedName: String?,
        processIdentifier: pid_t
    ) -> Bool {
        updateActiveApplication(
            ActiveApplicationSnapshot(
                bundleIdentifier: bundleIdentifier,
                localizedName: localizedName,
                processIdentifier: processIdentifier
            )
        )
    }

    @discardableResult
    private func updateActiveApplication(_ application: ActiveApplicationSnapshot) -> Bool {
        guard shouldAcceptActiveApplication(application) else {
            return false
        }

        stateLock.lock()
        let previousBundleID = currentBundleID
        currentBundleID = application.bundleIdentifier
        currentAppName = application.localizedName
        currentPID = application.processIdentifier
        stateLock.unlock()

        if previousBundleID != application.bundleIdentifier ||
            !isBrowser(application.bundleIdentifier) {
            clearBrowserContext()
        }

        return true
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

    private static func defaultIgnoredBundleIdentifiers() -> Set<String> {
        var identifiers: Set<String> = [
            "app.peyton.shorty",
            "app.peyton.shorty.appstore"
        ]

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            identifiers.insert(bundleIdentifier)
        }

        return identifiers
    }

    private static func snapshot(for app: NSRunningApplication) -> ActiveApplicationSnapshot {
        ActiveApplicationSnapshot(
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            processIdentifier: app.processIdentifier,
            isTerminated: app.isTerminated
        )
    }

    private func shouldAcceptActiveApplication(
        _ application: ActiveApplicationSnapshot
    ) -> Bool {
        guard !application.isTerminated else { return false }
        guard let bundleIdentifier = application.bundleIdentifier else { return true }
        return !ignoredBundleIdentifiers.contains(bundleIdentifier)
    }

    private func isBrowser(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return Self.browserBundleIDs.contains(id)
    }
}
