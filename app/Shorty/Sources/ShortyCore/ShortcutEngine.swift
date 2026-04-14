import AppKit
import Combine
import ServiceManagement

/// Top-level orchestrator for monitoring the active app, resolving adapters,
/// installing the keyboard event tap, and running the optional browser bridge.
public final class ShortcutEngine: ObservableObject {
    public static let firstRunCompleteDefaultsKey = "Shorty.FirstRun.Complete"
    public static let updateChecksEnabledDefaultsKey = "Shorty.Updates.AutomaticChecksEnabled"

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
    @Published public private(set) var shortcutProfile: UserShortcutProfile
    @Published public private(set) var updateStatus: UpdateStatus
    @Published public private(set) var safariExtensionStatus = SafariExtensionStatus()
    @Published public private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published public private(set) var isFirstRunComplete: Bool
    @Published public private(set) var generatedAdapterPreview: Adapter?
    @Published public private(set) var adapterGenerationMessage: String?

    /// Last error message kept for older UI callsites.
    @Published public var lastError: String?

    // MARK: - Private state

    private var cancellables = Set<AnyCancellable>()
    private var appChangeObserverInstalled = false
    private var adapterGenerationInFlight = Set<String>()
    private let userDefaults: UserDefaults
    private let safariExtensionUserDefaults: UserDefaults?

    // MARK: - Init

    public init(
        configuration: EngineConfiguration = .releaseDefault,
        userDefaults: UserDefaults = .standard,
        safariExtensionUserDefaults: UserDefaults? = UserDefaults(
            suiteName: SafariExtensionBridge.appGroupSuiteName
        )
    ) {
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.safariExtensionUserDefaults = safariExtensionUserDefaults
        self.shortcutProfile = .releaseDefault
        self.isFirstRunComplete = userDefaults.bool(
            forKey: Self.firstRunCompleteDefaultsKey
        )
        let marketingVersion = Self.bundleMarketingVersion()
        self.updateStatus = UpdateStatus(
            currentVersion: Self.bundleVersionString(marketingVersion: marketingVersion),
            sourceURL: Self.sourceURL(forVersion: marketingVersion),
            automaticChecksEnabled: userDefaults.bool(
                forKey: Self.updateChecksEnabledDefaultsKey
            )
        )
        self.launchAtLoginStatus = Self.currentLaunchAtLoginStatus()
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

        DistributedNotificationCenter.default()
            .publisher(for: SafariExtensionBridge.notificationName)
            .sink { [weak self] _ in
                self?.refreshSafariExtensionMessage()
            }
            .store(in: &cancellables)

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
        refreshSafariExtensionMessage()
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

    // MARK: - User configuration

    public func applyShortcutProfile(_ profile: UserShortcutProfile) {
        shortcutProfile = profile
        registry.applyShortcutProfile(profile)
    }

    public func markFirstRunComplete() {
        isFirstRunComplete = true
        userDefaults.set(true, forKey: Self.firstRunCompleteDefaultsKey)
    }

    public func resetFirstRunState() {
        isFirstRunComplete = false
        userDefaults.set(false, forKey: Self.firstRunCompleteDefaultsKey)
    }

    public func setAutomaticUpdateChecksEnabled(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: Self.updateChecksEnabledDefaultsKey)
        updateStatus = UpdateStatus(
            state: isEnabled ? .idle : .notConfigured,
            lastCheckedAt: updateStatus.lastCheckedAt,
            currentVersion: updateStatus.currentVersion,
            sourceURL: updateStatus.sourceURL,
            automaticChecksEnabled: isEnabled,
            detail: isEnabled
                ? "Shorty will use the direct-download update feed when Sparkle is bundled."
                : "Automatic direct-download update checks are off."
        )
    }

    public func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = Self.currentLaunchAtLoginStatus()
    }

    public func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            launchAtLoginStatus = LaunchAtLoginStatus(
                state: .needsAttention,
                detail: "Could not update Launch at Login: \(error.localizedDescription)"
            )
        }
    }

    public func recordUpdateCheckResult(
        state: UpdateStatus.State,
        detail: String,
        checkedAt: Date = Date()
    ) {
        updateStatus = UpdateStatus(
            state: state,
            lastCheckedAt: checkedAt,
            currentVersion: updateStatus.currentVersion,
            sourceURL: updateStatus.sourceURL,
            automaticChecksEnabled: updateStatus.automaticChecksEnabled,
            detail: detail
        )
    }

    public func recordSafariExtensionMessage(domain: String) {
        let normalized = DomainNormalizer.normalizedDomain(for: domain)
        appMonitor.updateBrowserContext(domain: normalized, source: .safariExtension)
        safariExtensionStatus = SafariExtensionStatus(
            state: .enabled,
            lastMessageAt: Date(),
            lastDomain: normalized,
            detail: "Safari reported \(normalized)."
        )
    }

    public func refreshSafariExtensionMessage() {
        guard let message = SafariExtensionBridge.readLastMessage(
            userDefaults: safariExtensionUserDefaults
        ) else {
            if safariExtensionStatus.state == .unknown {
                safariExtensionStatus = SafariExtensionStatus(
                    state: .bundled,
                    detail: "The Safari extension is bundled. Enable it in Safari Settings to report active web-app domains."
                )
            }
            return
        }

        switch message.kind {
        case .domainChanged:
            guard let domain = message.domain, !domain.isEmpty else { return }
            let normalized = DomainNormalizer.normalizedDomain(for: domain)
            appMonitor.updateBrowserContext(
                domain: normalized,
                source: .safariExtension
            )
            safariExtensionStatus = SafariExtensionStatus(
                state: .enabled,
                lastMessageAt: message.createdAt,
                lastDomain: normalized,
                detail: "Safari reported \(normalized)."
            )
        case .domainCleared:
            appMonitor.clearBrowserContext(source: .safariExtension)
            safariExtensionStatus = SafariExtensionStatus(
                state: .enabled,
                lastMessageAt: message.createdAt,
                lastDomain: nil,
                detail: "Safari is connected; the active tab is not a supported web app."
            )
        }
    }

    public func setSafariExtensionStatus(_ status: SafariExtensionStatus) {
        safariExtensionStatus = status
    }

    public func diagnosticSnapshot() -> RuntimeDiagnosticSnapshot {
        RuntimeDiagnosticSnapshot(
            engineStatus: status.title,
            permissionState: permissionState,
            currentAppName: appMonitor.currentAppName,
            currentBundleID: appMonitor.currentBundleID,
            effectiveAppID: appMonitor.effectiveAppID,
            browserContextSource: appMonitor.browserContextSource,
            webDomain: appMonitor.webAppDomain,
            bridgeStatus: browserBridge?.status.title ?? "Unavailable",
            safariExtensionStatus: safariExtensionStatus,
            eventsIntercepted: eventTap.eventsIntercepted,
            eventsRemapped: eventTap.eventsRemapped,
            adapterValidationMessages: registry.validationMessages
        )
    }

    public func supportBundle() -> SupportBundle {
        SupportBundle(
            diagnostics: diagnosticSnapshot(),
            shortcutProfile: shortcutProfile,
            adapters: registry.allAdapters.map(\.appIdentifier).sorted(),
            notes: shortcutProfile.conflicts().map(\.message)
        )
    }

    public func exportSupportBundle(to url: URL) throws {
        try supportBundle().encodedJSON().write(to: url, options: .atomic)
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

    private static func bundleMarketingVersion() -> String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private static func bundleVersionString(marketingVersion: String) -> String {
        let info = Bundle.main.infoDictionary
        let build = info?["CFBundleVersion"] as? String
        guard let build, !build.isEmpty, build != "Unknown" else {
            return marketingVersion
        }
        return "\(marketingVersion) (\(build))"
    }

    private static func sourceURL(forVersion version: String) -> URL? {
        guard !version.isEmpty, version != "Unknown" else {
            return UpdateStatus.defaultSourceURL
        }
        return URL(string: "https://github.com/peyton/shorty/releases/tag/v\(version)")
    }

    private static func currentLaunchAtLoginStatus() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return LaunchAtLoginStatus(
                state: .enabled,
                detail: "Shorty will open automatically when you sign in."
            )
        case .notRegistered:
            return LaunchAtLoginStatus(
                state: .notRegistered,
                detail: "Shorty will only open when you launch it yourself."
            )
        case .requiresApproval:
            return LaunchAtLoginStatus(
                state: .requiresApproval,
                detail: "Approve Shorty in System Settings > General > Login Items."
            )
        case .notFound:
            return LaunchAtLoginStatus(
                state: .notFound,
                detail: "macOS cannot register this copy. Move Shorty to Applications and try again."
            )
        @unknown default:
            return LaunchAtLoginStatus(
                state: .unknown,
                detail: "macOS returned an unknown Launch at Login state."
            )
        }
    }

    public static func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions(
            [promptKey: true] as CFDictionary
        )
    }
}
