import AppKit
import Combine

/// Top-level orchestrator that wires together the app monitor, adapter
/// registry, event tap, and (in Phase 2) menu introspector.
///
/// The engine is the single entry point for the rest of the app.
/// Create one at launch, call `start()`, and it handles everything.
///
/// ## Ownership graph
///
/// ```
/// ShortcutEngine
///   ├─ AppMonitor          (observes frontmost app)
///   ├─ AdapterRegistry     (resolves shortcuts → native actions)
///   ├─ EventTapManager     (intercepts and rewrites keyboard events)
///   ├─ MenuIntrospector?   (Phase 2: reads menus via AX)
///   └─ BrowserBridge?      (Phase 3: native messaging host)
/// ```
public final class ShortcutEngine: ObservableObject {

    // MARK: - Sub-components (public for UI binding)

    public let appMonitor: AppMonitor
    public let registry: AdapterRegistry
    public let eventTap: EventTapManager

    /// Phase 2: menu introspector for auto-generating adapters.
    public var menuIntrospector: MenuIntrospector?

    /// Phase 3: browser extension bridge.
    public var browserBridge: BrowserBridge?

    // MARK: - Published state

    /// `true` once the event tap is running.
    @Published public private(set) var isRunning: Bool = false

    /// Last error message, if any (e.g., missing Accessibility permission).
    @Published public var lastError: String?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init() {
        self.appMonitor = AppMonitor()
        self.registry = AdapterRegistry()
        self.eventTap = EventTapManager(registry: registry,
                                        appMonitor: appMonitor)
        self.menuIntrospector = MenuIntrospector()
        self.browserBridge = BrowserBridge(appMonitor: appMonitor)
    }

    // MARK: - Lifecycle

    /// Start the engine. Call once at launch.
    public func start() {
        guard !isRunning else { return }

        // 1. Start the event tap.
        let tapOK = eventTap.start()
        if !tapOK {
            lastError = "Could not install keyboard tap. "
                + "Please grant Accessibility permission in "
                + "System Settings → Privacy & Security → Accessibility."
        }
        isRunning = tapOK

        // 2. Observe frontmost app changes for Phase 2 auto-adapter generation.
        appMonitor.$currentBundleID
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] bundleID in
                self?.onAppChanged(bundleID: bundleID)
            }
            .store(in: &cancellables)

        // 3. Phase 3: start browser bridge if available.
        browserBridge?.start()
    }

    /// Stop the engine and clean up.
    public func stop() {
        eventTap.stop()
        browserBridge?.stop()
        cancellables.removeAll()
        isRunning = false
    }

    // MARK: - App change handler

    private func onAppChanged(bundleID: String) {
        // If we already have an adapter (any source), nothing to do.
        if registry.hasAdapter(for: bundleID) {
            return
        }

        // Phase 2: try to auto-generate an adapter via menu introspection.
        guard let introspector = menuIntrospector else { return }

        let pid = appMonitor.currentPID
        let appName = appMonitor.currentAppName ?? bundleID

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            guard let adapter = introspector.generateAdapter(
                bundleID: bundleID,
                appName: appName,
                pid: pid,
                canonicals: CanonicalShortcut.defaults
            ) else { return }

            DispatchQueue.main.async {
                // Save to disk (best-effort) and reload the in-memory registry.
                try? self.registry.saveAutoAdapter(adapter)
                self.registry.reloadAdapters()
            }
        }
    }

    // MARK: - Convenience

    /// Check whether the process has Accessibility permission.
    public static var hasAccessibilityPermission: Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions(
            [promptKey: false] as CFDictionary
        )
    }

    /// Prompt the user to grant Accessibility permission.
    public static func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions(
            [promptKey: true] as CFDictionary
        )
    }
}
