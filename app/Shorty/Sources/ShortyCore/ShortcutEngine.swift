import AppKit
import Combine

/// Top-level orchestrator for monitoring the active app, resolving adapters,
/// installing the keyboard event tap, and running the optional browser bridge.
public final class ShortcutEngine: ObservableObject {

    // MARK: - Sub-components

    public let appMonitor: AppMonitor
    public let registry: AdapterRegistry
    public let eventTap: EventTapManager
    public let configuration: EngineConfiguration

    public var menuIntrospector: MenuIntrospector?
    public var browserBridge: BrowserBridge?

    // MARK: - Published state

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var status: EngineStatus = .stopped
    @Published public private(set) var permissionState: PermissionState = .unknown
    @Published public private(set) var generatedAdapterPreview: Adapter?
    @Published public private(set) var adapterGenerationMessage: String?

    /// Last error message kept for older UI callsites.
    @Published public var lastError: String?

    // MARK: - Private state

    private var cancellables = Set<AnyCancellable>()
    private var appChangeObserverInstalled = false
    private var adapterGenerationInFlight = Set<String>()

    // MARK: - Init

    public init(
        configuration: EngineConfiguration = .releaseDefault,
        userDefaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.appMonitor = AppMonitor()
        self.registry = AdapterRegistry()
        self.eventTap = EventTapManager(
            registry: registry,
            appMonitor: appMonitor,
            userDefaults: userDefaults
        )
        self.menuIntrospector = MenuIntrospector()
        self.browserBridge = BrowserBridge(
            appMonitor: appMonitor,
            configuration: configuration
        )

        eventTap.$isEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self, self.isRunning else { return }
                self.setStatus(isEnabled ? .running : .disabled)
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    public func start() {
        guard status != .starting else { return }
        guard !isRunning else {
            setStatus(eventTap.isEnabled ? .running : .disabled)
            return
        }

        setStatus(.starting)
        installAppChangeObserverIfNeeded()
        browserBridge?.start()
        refreshPermissionState()

        guard permissionState.isGranted else {
            setStatus(.permissionRequired)
            return
        }

        let tapOK = eventTap.start()
        guard tapOK else {
            setStatus(.failed(
                "Could not install the keyboard tap. Check Accessibility permission and try again."
            ))
            return
        }

        isRunning = true
        setStatus(eventTap.isEnabled ? .running : .disabled)
    }

    public func stop() {
        eventTap.stop()
        browserBridge?.stop()
        adapterGenerationInFlight.removeAll()
        generatedAdapterPreview = nil
        adapterGenerationMessage = nil
        isRunning = false
        setStatus(.stopped)
    }

    public func checkAccessibilityAndRetry() {
        refreshPermissionState()
        guard permissionState.isGranted else {
            setStatus(.permissionRequired)
            return
        }

        if !isRunning {
            start()
            return
        }

        setStatus(eventTap.isEnabled ? .running : .disabled)
    }

    public func refreshPermissionState() {
        permissionState = Self.hasAccessibilityPermission ? .granted : .notGranted
    }

    // MARK: - Adapter generation

    public func generateAdapterForCurrentApp() {
        guard let bundleID = appMonitor.currentBundleID else {
            adapterGenerationMessage = "No active app is available."
            return
        }

        if registry.hasAdapter(for: bundleID) {
            adapterGenerationMessage = "Shorty already has an adapter for this app."
            return
        }

        generateAdapterPreview(
            bundleID: bundleID,
            appName: appMonitor.currentAppName ?? bundleID,
            pid: appMonitor.currentPID,
            saveAutomatically: false
        )
    }

    public func saveGeneratedAdapterPreview() {
        guard let adapter = generatedAdapterPreview else {
            adapterGenerationMessage = "No generated adapter is waiting to save."
            return
        }

        do {
            try registry.saveAutoAdapter(adapter)
            generatedAdapterPreview = nil
            adapterGenerationMessage = "Saved adapter for \(adapter.appName)."
        } catch {
            adapterGenerationMessage = "Could not save generated adapter: \(error)"
            ShortyLog.engine.error("Failed to save generated adapter: \(error.localizedDescription)")
        }
    }

    public func discardGeneratedAdapterPreview() {
        generatedAdapterPreview = nil
        adapterGenerationMessage = nil
    }

    private func installAppChangeObserverIfNeeded() {
        guard !appChangeObserverInstalled else { return }
        appChangeObserverInstalled = true

        appMonitor.$currentBundleID
            .removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] bundleID in
                self?.onAppChanged(bundleID: bundleID)
            }
            .store(in: &cancellables)
    }

    private func onAppChanged(bundleID: String) {
        guard configuration.autoGenerateMenuAdapters else { return }
        guard !registry.hasAdapter(for: bundleID) else { return }

        generateAdapterPreview(
            bundleID: bundleID,
            appName: appMonitor.currentAppName ?? bundleID,
            pid: appMonitor.currentPID,
            saveAutomatically: true
        )
    }

    private func generateAdapterPreview(
        bundleID: String,
        appName: String,
        pid: pid_t,
        saveAutomatically: Bool
    ) {
        guard let introspector = menuIntrospector else {
            adapterGenerationMessage = "Menu adapter generation is unavailable."
            return
        }
        guard adapterGenerationInFlight.insert(bundleID).inserted else {
            adapterGenerationMessage = "Already checking \(appName)."
            return
        }

        generatedAdapterPreview = nil
        adapterGenerationMessage = "Reading menus for \(appName)..."

        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.adapterGenerationInFlight.remove(bundleID) != nil else { return }
            self.adapterGenerationMessage = "Timed out while reading menus for \(appName)."
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + configuration.adapterGenerationTimeout,
            execute: timeout
        )

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let adapter = introspector.generateAdapter(
                bundleID: bundleID,
                appName: appName,
                pid: pid,
                canonicals: CanonicalShortcut.defaults
            )

            DispatchQueue.main.async {
                timeout.cancel()
                guard self.adapterGenerationInFlight.remove(bundleID) != nil else { return }
                guard self.appMonitor.currentBundleID == bundleID else {
                    self.adapterGenerationMessage = "Skipped generated adapter because the active app changed."
                    return
                }

                guard let adapter else {
                    self.adapterGenerationMessage = "No matching shortcuts were found in \(appName)."
                    return
                }

                if saveAutomatically {
                    do {
                        try self.registry.saveAutoAdapter(adapter)
                        self.adapterGenerationMessage = "Saved adapter for \(adapter.appName)."
                    } catch {
                        self.adapterGenerationMessage = "Could not save generated adapter: \(error)"
                    }
                } else {
                    self.generatedAdapterPreview = adapter
                    self.adapterGenerationMessage = "Generated \(adapter.mappings.count) mappings for \(adapter.appName). Review before saving."
                }
            }
        }
    }

    // MARK: - Status

    private func setStatus(_ newStatus: EngineStatus) {
        status = newStatus
        switch newStatus {
        case .failed(let message):
            lastError = message
        case .permissionRequired:
            lastError = nil
        case .stopped, .starting, .running, .disabled:
            lastError = nil
        }
    }

    // MARK: - Convenience

    public static var hasAccessibilityPermission: Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions(
            [promptKey: false] as CFDictionary
        )
    }

    public static func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions(
            [promptKey: true] as CFDictionary
        )
    }
}
