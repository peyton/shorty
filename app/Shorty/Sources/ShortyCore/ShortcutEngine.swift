import AppKit
import Combine
#if canImport(SafariServices)
import SafariServices
#endif
import ServiceManagement

/// Top-level orchestrator for monitoring the active app, resolving adapters,
/// installing the keyboard event tap, and running the optional browser bridge.
public final class ShortcutEngine: ObservableObject {
    public static let firstRunCompleteDefaultsKey = "Shorty.FirstRun.Complete"
    public static let updateChecksEnabledDefaultsKey = "Shorty.Updates.AutomaticChecksEnabled"
    public static let globalPauseUntilDefaultsKey = "Shorty.GlobalPauseUntil"
    public static let adapterRevisionsDefaultsKey = "Shorty.AdapterRevisions"

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
    @Published public private(set) var isWaitingForAccessibilityPermission: Bool = false
    @Published public private(set) var shortcutProfile: UserShortcutProfile
    @Published public private(set) var updateStatus: UpdateStatus
    @Published public private(set) var safariExtensionStatus = SafariExtensionStatus()
    @Published public private(set) var launchAtLoginStatus: LaunchAtLoginStatus
    @Published public private(set) var bridgeInstallStatuses: [BridgeInstallStatus]
    @Published public private(set) var isFirstRunComplete: Bool
    @Published public private(set) var generatedAdapterPreview: Adapter?
    @Published public private(set) var generatedAdapterReview: AdapterReview?
    @Published public private(set) var adapterRevisions: [AdapterRevision] = []
    @Published public private(set) var adapterGenerationMessage: String?
    @Published public private(set) var globalPauseUntil: Date?
    @Published public private(set) var settingsFeedbackMessage: String?

    /// Last error message kept for older UI callsites.
    @Published public var lastError: String?

    // MARK: - Private state

    private var cancellables = Set<AnyCancellable>()
    private var appChangeObserverInstalled = false
    private var adapterGenerationInFlight = Set<String>()
    private var accessibilityPermissionTimer: Timer?
    private var tapFailureDates: [Date] = []
    private var tapSafeModeUntil: Date?
    private let userDefaults: UserDefaults
    private let safariExtensionUserDefaults: UserDefaults?
    private let bridgeInstallManager: BrowserBridgeInstallManager
    private let tapFailureLimit = 3
    private let tapFailureWindow: TimeInterval = 5 * 60
    private let tapSafeModeDuration: TimeInterval = 5 * 60

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
        let loadedShortcutProfile = Self.loadShortcutProfile(userDefaults: userDefaults)
        self.shortcutProfile = loadedShortcutProfile
        self.globalPauseUntil = userDefaults.object(
            forKey: Self.globalPauseUntilDefaultsKey
        ) as? Date
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
        self.bridgeInstallManager = BrowserBridgeInstallManager()
        self.bridgeInstallStatuses = bridgeInstallManager.statuses()
        self.adapterRevisions = Self.loadAdapterRevisions(userDefaults: userDefaults)
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
        self.registry.applyShortcutProfile(loadedShortcutProfile)

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

        appMonitor.$currentBundleID
            .sink { [weak self] _ in
                self?.appMonitor.expireStaleBrowserContext()
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
        expireGlobalPauseIfNeeded()
        installAppChangeObserverIfNeeded()
        refreshSafariExtensionMessage()
        refreshSafariExtensionState()
        refreshBridgeInstallStatuses()
        refreshLaunchAtLoginStatus()
        if configuration.startsBrowserBridge {
            browserBridge?.start()
        }
        refreshPermissionState()

        guard configuration.startsEventTap else {
            isRunning = true
            setStatus(.disabled)
            lastError = "This build does not start the keyboard event tap."
            return
        }

        guard permissionState.isGranted else {
            setStatus(.permissionRequired)
            startAccessibilityPermissionMonitor(waitingForUser: false)
            return
        }

        guard canAttemptEventTapStart() else {
            return
        }

        let tapOK = eventTap.start()
        guard tapOK else {
            recordTapStartFailure()
            return
        }

        clearTapStartFailures()
        isRunning = true
        applyPauseStateIfNeeded()
        setStatus(eventTap.isEnabled ? .running : .disabled)
    }

    public func stop() {
        stopAccessibilityPermissionMonitor()
        eventTap.stop()
        browserBridge?.stop()
        adapterGenerationInFlight.removeAll()
        generatedAdapterPreview = nil
        generatedAdapterReview = nil
        adapterGenerationMessage = nil
        isRunning = false
        setStatus(.stopped)
    }

    public func checkAccessibilityAndRetry() {
        expireGlobalPauseIfNeeded()
        refreshPermissionState()
        guard permissionState.isGranted else {
            setStatus(.permissionRequired)
            startAccessibilityPermissionMonitor(waitingForUser: false)
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
        if permissionState.isGranted {
            stopAccessibilityPermissionMonitor()
        }
    }

    public func openAccessibilitySettings() {
        Self.requestAccessibilityPermission()
        refreshPermissionState()
        guard !permissionState.isGranted else {
            checkAccessibilityAndRetry()
            return
        }
        setStatus(.permissionRequired)
        startAccessibilityPermissionMonitor(waitingForUser: true)
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
            recordAdapterRevision(
                adapter,
                summary: "Saved generated adapter with \(adapter.mappings.count) mappings."
            )
            generatedAdapterPreview = nil
            adapterGenerationMessage = "Saved adapter for \(adapter.appName)."
            generatedAdapterReview = nil
        } catch {
            adapterGenerationMessage = "Could not save generated adapter: \(error)"
            ShortyLog.engine.error("Failed to save generated adapter: \(error.localizedDescription)")
        }
    }

    public func discardGeneratedAdapterPreview() {
        generatedAdapterPreview = nil
        generatedAdapterReview = nil
        adapterGenerationMessage = nil
    }

    // MARK: - User configuration

    public func applyShortcutProfile(_ profile: UserShortcutProfile) {
        shortcutProfile = profile
        registry.applyShortcutProfile(profile)
        persistShortcutProfile()
    }

    public func updateShortcut(_ shortcutID: String, keyCombo: KeyCombo) {
        var next = shortcutProfile
        next.updateShortcut(shortcutID, keyCombo: keyCombo)
        applyShortcutProfile(next)
        settingsFeedbackMessage = "Updated shortcut."
    }

    public func resetShortcut(_ shortcutID: String) {
        var next = shortcutProfile
        next.resetShortcut(shortcutID)
        applyShortcutProfile(next)
        settingsFeedbackMessage = "Reset shortcut."
    }

    public func setShortcut(_ shortcutID: String, enabled: Bool) {
        var next = shortcutProfile
        next.setShortcut(shortcutID, enabled: enabled)
        applyShortcutProfile(next)
        settingsFeedbackMessage = enabled ? "Shortcut enabled." : "Shortcut disabled."
    }

    public func setAdapter(_ appIdentifier: String, enabled: Bool) {
        var next = shortcutProfile
        next.setAdapter(appIdentifier, enabled: enabled)
        applyShortcutProfile(next)
        settingsFeedbackMessage = enabled ? "App shortcuts resumed." : "App shortcuts paused."
    }

    public func setMapping(
        adapterID: String,
        canonicalID: String,
        enabled: Bool
    ) {
        var next = shortcutProfile
        next.setMapping(
            adapterID: adapterID,
            canonicalID: canonicalID,
            enabled: enabled
        )
        applyShortcutProfile(next)
        settingsFeedbackMessage = enabled ? "Mapping enabled." : "Mapping disabled."
    }

    public func deleteAdapter(appIdentifier: String) {
        do {
            try registry.deleteEditableAdapter(appIdentifier: appIdentifier)
            settingsFeedbackMessage = "Deleted adapter."
        } catch {
            settingsFeedbackMessage = "Could not delete adapter: \(error)"
        }
    }

    public func exportAdapter(appIdentifier: String, to url: URL) throws {
        try registry.exportAdapter(appIdentifier: appIdentifier, to: url)
        settingsFeedbackMessage = "Exported adapter."
    }

    public func importAdapter(from url: URL) {
        do {
            let adapter = try registry.importUserAdapter(from: url)
            recordAdapterRevision(
                adapter,
                summary: "Imported user adapter with \(adapter.mappings.count) mappings."
            )
            settingsFeedbackMessage = "Imported adapter for \(adapter.appName)."
        } catch {
            settingsFeedbackMessage = "Could not import adapter: \(error)"
        }
    }

    public func pauseCurrentApp() {
        guard let appID = appMonitor.snapshot().effectiveAppID else { return }
        setAdapter(appID, enabled: false)
    }

    public func resumeCurrentApp() {
        guard let appID = appMonitor.snapshot().effectiveAppID else { return }
        setAdapter(appID, enabled: true)
    }

    public func pauseForDuration(_ duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        globalPauseUntil = until
        userDefaults.set(until, forKey: Self.globalPauseUntilDefaultsKey)
        eventTap.isEnabled = false
        setStatus(.disabled)
        settingsFeedbackMessage = "Paused until \(Self.relativeTimeFormatter.localizedString(for: until, relativeTo: Date()))."
    }

    public func resumeGlobalPause() {
        globalPauseUntil = nil
        userDefaults.removeObject(forKey: Self.globalPauseUntilDefaultsKey)
        eventTap.isEnabled = true
        setStatus(isRunning ? .running : status)
        settingsFeedbackMessage = "Shortcut translation resumed."
    }

    public func markFirstRunComplete() {
        isFirstRunComplete = true
        userDefaults.set(true, forKey: Self.firstRunCompleteDefaultsKey)
        settingsFeedbackMessage = "Setup complete. Shorty is ready when Accessibility access is enabled."
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

    public func refreshBridgeInstallStatuses() {
        bridgeInstallStatuses = bridgeInstallManager.statuses()
    }

    public func refreshDailyStatuses() {
        refreshLaunchAtLoginStatus()
        refreshBridgeInstallStatuses()
        refreshSafariExtensionMessage()
        refreshSafariExtensionState()
        appMonitor.expireStaleBrowserContext()
        expireGlobalPauseIfNeeded()
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

    public func checkForUpdates() {
        guard let sourceURL = updateStatus.sourceURL else {
            recordUpdateCheckResult(
                state: .failed,
                detail: "No update feed is configured for this build."
            )
            return
        }
        NSWorkspace.shared.open(sourceURL)
        recordUpdateCheckResult(
            state: .idle,
            detail: "Opened Shorty's release page. Sparkle appcast checks will replace this when bundled."
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

    public func refreshSafariExtensionState() {
#if canImport(SafariServices)
        let bundleIdentifier = SafariExtensionStatus.bundleIdentifier(
            forAppBundleIdentifier: Bundle.main.bundleIdentifier
        )
        SFSafariExtensionManager.getStateOfSafariExtension(
            withIdentifier: bundleIdentifier
        ) { [weak self] state, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.safariExtensionStatus = SafariExtensionStatus(
                        state: .needsAttention,
                        bundleIdentifier: bundleIdentifier,
                        lastMessageAt: self.safariExtensionStatus.lastMessageAt,
                        lastDomain: self.safariExtensionStatus.lastDomain,
                        detail: "Could not read Safari extension state: \(error.localizedDescription)"
                    )
                    return
                }
                guard let state else {
                    self.safariExtensionStatus = SafariExtensionStatus(
                        state: .missing,
                        bundleIdentifier: bundleIdentifier,
                        lastMessageAt: self.safariExtensionStatus.lastMessageAt,
                        lastDomain: self.safariExtensionStatus.lastDomain,
                        detail: "Safari did not find Shorty's extension."
                    )
                    return
                }
                if self.safariExtensionStatus.lastMessageAt != nil,
                   self.safariExtensionStatus.state == .enabled {
                    return
                }
                self.safariExtensionStatus = SafariExtensionStatus(
                    state: state.isEnabled ? .enabled : .disabled,
                    bundleIdentifier: bundleIdentifier,
                    lastMessageAt: self.safariExtensionStatus.lastMessageAt,
                    lastDomain: self.safariExtensionStatus.lastDomain,
                    detail: state.isEnabled
                        ? "Safari extension is enabled."
                        : "Enable Shorty in Safari Settings > Extensions."
                )
            }
        }
#endif
    }

    public func setSafariExtensionStatus(_ status: SafariExtensionStatus) {
        safariExtensionStatus = status
    }

    public func diagnosticSnapshot() -> RuntimeDiagnosticSnapshot {
        eventTap.flushPendingDiagnostics()
        let appSnapshot = appMonitor.snapshot()
        return RuntimeDiagnosticSnapshot(
            engineStatus: status.title,
            permissionState: permissionState,
            currentAppName: appSnapshot.currentAppName,
            currentBundleID: appSnapshot.currentBundleID,
            effectiveAppID: appSnapshot.effectiveAppID,
            browserContextSource: appSnapshot.browserContextSource,
            webDomain: appSnapshot.webAppDomain,
            bridgeStatus: redacted(browserBridge?.status.detail ?? "Unavailable"),
            safariExtensionStatus: safariExtensionStatus,
            eventsIntercepted: eventTap.eventsIntercepted,
            eventsMatched: eventTap.shortcutsMatched,
            eventsRemapped: eventTap.eventsRemapped,
            eventsPassedThrough: eventTap.counters.eventsPassedThrough,
            menuActionsInvoked: eventTap.counters.menuActionsInvoked,
            menuActionsSucceeded: eventTap.counters.menuActionsSucceeded,
            menuActionsFailed: eventTap.counters.menuActionsFailed,
            accessibilityActionsInvoked: eventTap.counters.accessibilityActionsInvoked,
            accessibilityActionsSucceeded: eventTap.counters.accessibilityActionsSucceeded,
            accessibilityActionsFailed: eventTap.counters.accessibilityActionsFailed,
            contextGuardsApplied: eventTap.counters.contextGuardsApplied,
            lastAction: eventTap.lastAction,
            distributionMode: Self.distributionMode(),
            adapterValidationMessages: registry.validationMessages
        )
    }

    public func supportBundle() -> SupportBundle {
        let adapters = registry.allAdapters
        let adapterIDs = adapters.map(\.appIdentifier).sorted()
        let adapterCountsBySource = Dictionary(
            grouping: adapters,
            by: { $0.source.rawValue }
        ).mapValues(\.count)
        let activeAvailability = registry.availability(
            for: appMonitor.effectiveAppID,
            displayName: appMonitor.currentAppName
        )

        eventTap.flushPendingDiagnostics()
        return SupportBundle(
            summary: SupportBundleSummary(
                appVersion: updateStatus.currentVersion,
                updateStatus: updateStatus,
                launchAtLoginStatus: launchAtLoginStatus,
                bridgeInstallStatuses: bridgeInstallStatuses.map(redacted),
                adapterRevisionCount: adapterRevisions.count,
                adapterCount: adapterIDs.count,
                adapterCountsBySource: adapterCountsBySource,
                supportedWebDomains: DomainNormalizer.supportedWebAppDomains.sorted(),
                validationWarningCount: registry.validationMessages.count,
                activeAvailability: activeAvailability,
                generatedAdapterReview: generatedAdapterReview
            ),
            diagnostics: diagnosticSnapshot(),
            shortcutProfile: shortcutProfile,
            adapters: adapterIDs,
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
        generatedAdapterReview = nil
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
                        self.recordAdapterRevision(
                            adapter,
                            summary: "Saved generated adapter with \(adapter.mappings.count) mappings."
                        )
                        self.adapterGenerationMessage = "Saved adapter for \(adapter.appName)."
                    } catch {
                        self.adapterGenerationMessage = "Could not save generated adapter: \(error)"
                    }
                } else {
                    self.generatedAdapterPreview = adapter
                    self.generatedAdapterReview = Self.reviewGeneratedAdapter(adapter)
                    self.adapterGenerationMessage = "Generated \(adapter.mappings.count) mappings for \(adapter.appName). Review before saving."
                }
            }
        }
    }

    public static func reviewGeneratedAdapter(
        _ adapter: Adapter,
        canonicals: [CanonicalShortcut] = CanonicalShortcut.defaults
    ) -> AdapterReview {
        let canonicalIDs = Set(canonicals.map(\.id))
        let mappedIDs = Set(adapter.mappings.map(\.canonicalID))
        let coverageRatio = canonicals.isEmpty
            ? 0
            : Double(mappedIDs.intersection(canonicalIDs).count) / Double(canonicals.count)
        let mappingCount = adapter.mappings.count
        let keyRemapCount = adapter.mappings.filter { $0.method == .keyRemap }.count
        let menuInvokeCount = adapter.mappings.filter { $0.method == .menuInvoke }.count
        let passthroughCount = adapter.mappings.filter { $0.method == .passthrough }.count
        let axActionCount = adapter.mappings.filter { $0.method == .axAction }.count
        let riskyIDs = Set(["submit_field", "newline_in_field"])
        let riskyMappings = adapter.mappings.filter { riskyIDs.contains($0.canonicalID) }
        let unknownIDs = mappedIDs.subtracting(canonicalIDs)

        var confidence = 0.35 + (coverageRatio * 0.45)
        if keyRemapCount > 0 {
            confidence += 0.08
        }
        if menuInvokeCount > keyRemapCount {
            confidence -= 0.12
        }
        if !riskyMappings.isEmpty {
            confidence -= 0.10
        }
        confidence = min(max(confidence, 0.10), 0.98)

        var reasons = [
            "Matched \(mappingCount) shortcut\(mappingCount == 1 ? "" : "s") from the app's menus.",
            "\(Int((coverageRatio * 100).rounded()))% of Shorty's canonical shortcuts are covered."
        ]
        if keyRemapCount > 0 {
            reasons.append("\(keyRemapCount) mapping\(keyRemapCount == 1 ? "" : "s") can use direct key remapping.")
        }
        if passthroughCount > 0 {
            reasons.append("\(passthroughCount) mapping\(passthroughCount == 1 ? "" : "s") already match Shorty's default keys.")
        }
        if axActionCount > 0 {
            reasons.append("\(axActionCount) mapping\(axActionCount == 1 ? "" : "s") use direct Accessibility actions.")
        }

        var warnings: [String] = []
        if coverageRatio < 0.35 {
            warnings.append("Low coverage. Save only if these are the shortcuts you need every day.")
        }
        if !riskyMappings.isEmpty {
            let names = riskyMappings.map(\.canonicalID).sorted().joined(separator: ", ")
            warnings.append("Review text-entry behavior before saving: \(names).")
        }
        if menuInvokeCount > 0 {
            warnings.append("Menu-invoked shortcuts depend on the app's menu titles staying stable.")
        }
        if !unknownIDs.isEmpty {
            warnings.append("Unknown canonical shortcut IDs: \(unknownIDs.sorted().joined(separator: ", ")).")
        }

        return AdapterReview(
            adapterIdentifier: adapter.appIdentifier,
            confidence: confidence,
            reasons: reasons,
            warnings: warnings,
            requiresExplicitApproval: !riskyMappings.isEmpty || confidence < 0.5
        )
    }

    private func recordAdapterRevision(_ adapter: Adapter, summary: String) {
        adapterRevisions.insert(
            AdapterRevision(
                adapterIdentifier: adapter.appIdentifier,
                summary: summary,
                adapter: adapter
            ),
            at: 0
        )
        if adapterRevisions.count > 20 {
            adapterRevisions.removeLast(adapterRevisions.count - 20)
        }
        persistAdapterRevisions()
    }

    private func persistShortcutProfile() {
        do {
            userDefaults.set(
                try shortcutProfile.encodedJSON(),
                forKey: UserShortcutProfile.defaultsKey
            )
        } catch {
            ShortyLog.engine.error("Failed to persist shortcut profile: \(error.localizedDescription)")
        }
    }

    private func persistAdapterRevisions() {
        do {
            userDefaults.set(
                try JSONEncoder().encode(adapterRevisions),
                forKey: Self.adapterRevisionsDefaultsKey
            )
        } catch {
            ShortyLog.engine.error("Failed to persist adapter revisions: \(error.localizedDescription)")
        }
    }

    private static func loadShortcutProfile(userDefaults: UserDefaults) -> UserShortcutProfile {
        guard let data = userDefaults.data(forKey: UserShortcutProfile.defaultsKey),
              let profile = try? UserShortcutProfile.decode(from: data)
        else {
            return .releaseDefault
        }
        return profile
    }

    private static func loadAdapterRevisions(userDefaults: UserDefaults) -> [AdapterRevision] {
        guard let data = userDefaults.data(forKey: adapterRevisionsDefaultsKey),
              let revisions = try? JSONDecoder().decode([AdapterRevision].self, from: data)
        else {
            return []
        }
        return Array(revisions.prefix(20))
    }

    private func expireGlobalPauseIfNeeded(now: Date = Date()) {
        guard let pauseUntil = globalPauseUntil, now >= pauseUntil else { return }
        resumeGlobalPause()
    }

    private func applyPauseStateIfNeeded(now: Date = Date()) {
        guard let pauseUntil = globalPauseUntil else { return }
        if now >= pauseUntil {
            resumeGlobalPause()
        } else {
            eventTap.isEnabled = false
            setStatus(.disabled)
        }
    }

    private func redacted(_ status: BridgeInstallStatus) -> BridgeInstallStatus {
        BridgeInstallStatus(
            browser: status.browser,
            state: status.state,
            manifestPath: status.manifestPath.map(redacted),
            helperPath: status.helperPath.map(redacted),
            detail: redacted(status.detail)
        )
    }

    private func redacted(_ text: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !home.isEmpty else { return text }
        return text.replacingOccurrences(of: home, with: "~")
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

    private func canAttemptEventTapStart(now: Date = Date()) -> Bool {
        guard let tapSafeModeUntil else {
            return true
        }
        if tapSafeModeUntil <= now {
            self.tapSafeModeUntil = nil
            tapFailureDates.removeAll()
            return true
        }
        setStatus(.failed(
            "Shorty paused the keyboard tap after repeated startup failures. Check Accessibility permission, then try again in a few minutes."
        ))
        return false
    }

    private func recordTapStartFailure(now: Date = Date()) {
        tapFailureDates = tapFailureDates.filter {
            now.timeIntervalSince($0) <= tapFailureWindow
        }
        tapFailureDates.append(now)

        if tapFailureDates.count >= tapFailureLimit {
            tapSafeModeUntil = now.addingTimeInterval(tapSafeModeDuration)
            eventTap.isEnabled = false
            setStatus(.failed(
                "Shorty paused the keyboard tap after repeated startup failures. Check Accessibility permission, then try again in five minutes."
            ))
            return
        }

        setStatus(.failed(
            "Could not install the keyboard tap. Check Accessibility permission and try again."
        ))
    }

    private func clearTapStartFailures() {
        tapFailureDates.removeAll()
        tapSafeModeUntil = nil
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

    private static var relativeTimeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }

    private static func distributionMode() -> String {
#if DEBUG
        return "Debug"
#else
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        if bundleIdentifier.contains("appstore") {
            return "App Store candidate"
        }
        return "Direct download"
#endif
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

    private func startAccessibilityPermissionMonitor(waitingForUser: Bool) {
        if waitingForUser {
            isWaitingForAccessibilityPermission = true
        }
        guard accessibilityPermissionTimer == nil else { return }

        accessibilityPermissionTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.pollAccessibilityPermission()
        }
    }

    private func stopAccessibilityPermissionMonitor() {
        accessibilityPermissionTimer?.invalidate()
        accessibilityPermissionTimer = nil
        isWaitingForAccessibilityPermission = false
    }

    private func pollAccessibilityPermission() {
        permissionState = Self.hasAccessibilityPermission ? .granted : .notGranted
        guard permissionState.isGranted else {
            setStatus(.permissionRequired)
            return
        }

        stopAccessibilityPermissionMonitor()
        checkAccessibilityAndRetry()
    }
}
