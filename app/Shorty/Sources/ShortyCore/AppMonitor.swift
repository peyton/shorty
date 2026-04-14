import AppKit
import Combine

/// Tracks which application is frontmost, publishing changes reactively.
///
/// AppMonitor observes `NSWorkspace.didActivateApplicationNotification`
/// and caches the current bundle identifier. The EventTapManager reads
/// this on every keystroke (via the fast `currentAppID` property) rather
/// than querying NSWorkspace each time.
public final class AppMonitor: ObservableObject {

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
        if let domain = webAppDomain,
           isBrowser(currentBundleID) {
            return DomainNormalizer.adapterIdentifier(for: domain)
        }
        return currentBundleID
    }

    private var cancellable: AnyCancellable?

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
        let previousBundleID = currentBundleID
        currentBundleID = bundleIdentifier
        currentAppName = localizedName
        currentPID = processIdentifier

        if previousBundleID != bundleIdentifier || !isBrowser(bundleIdentifier) {
            clearBrowserContext()
        }
    }

    public func updateBrowserContext(
        domain: String,
        source: BrowserContextSource
    ) {
        webAppDomain = DomainNormalizer.normalizedDomain(for: domain)
        browserContextSource = source
    }

    public func clearBrowserContext(source: BrowserContextSource? = nil) {
        guard source == nil || source == browserContextSource else { return }
        webAppDomain = nil
        browserContextSource = .none
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
