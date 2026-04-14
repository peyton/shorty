import AppKit
import Combine
import SafariServices
import ShortyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var snapshotStore: SettingsSnapshotStore
    private let actions: SettingsActions

    init(engine: ShortcutEngine) {
        _snapshotStore = StateObject(wrappedValue: SettingsSnapshotStore(engine: engine))
        self.actions = .live(engine: engine)
    }

    var body: some View {
        SettingsContentView(
            snapshot: snapshotStore.snapshot,
            actions: actions
        )
    }
}

private final class SettingsSnapshotStore: ObservableObject {
    @Published private(set) var snapshot: SettingsSnapshot

    private let engine: ShortcutEngine
    private let versionBuild: String
    private var shortcutConflicts: [ShortcutConflict]
    private var sortedAdapters: [Adapter]
    private var cancellables = Set<AnyCancellable>()
    private var refreshScheduled = false

    init(engine: ShortcutEngine) {
        self.engine = engine
        self.versionBuild = Self.bundleVersionBuild()
        self.shortcutConflicts = engine.shortcutProfile.conflicts()
        self.sortedAdapters = Self.sortedAdapters(engine.registry.allAdapters)
        self.snapshot = SettingsSnapshot.live(
            engine: engine,
            versionBuild: versionBuild,
            shortcutConflicts: shortcutConflicts,
            adapters: sortedAdapters
        )

        bind()
    }

    private func bind() {
        observe(engine.$status) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$permissionState) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$isWaitingForAccessibilityPermission) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$updateStatus) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$safariExtensionStatus) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$launchAtLoginStatus) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$isFirstRunComplete) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$generatedAdapterPreview) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$adapterGenerationMessage) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$shortcutProfile) { [weak self] profile in
            guard let self else { return }
            self.shortcutConflicts = profile.conflicts()
            self.scheduleRefresh()
        }

        observe(engine.registry.$adapters) { [weak self] adapters in
            guard let self else { return }
            self.sortedAdapters = Self.sortedAdapters(Array(adapters.values))
            self.scheduleRefresh()
        }
        observe(engine.registry.$validationMessages) { [weak self] _ in
            self?.scheduleRefresh()
        }

        observe(engine.appMonitor.$currentBundleID) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.appMonitor.$currentAppName) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.appMonitor.$webAppDomain) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.appMonitor.$browserContextSource) { [weak self] _ in
            self?.scheduleRefresh()
        }

        observe(engine.eventTap.$eventsIntercepted) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.eventTap.$eventsRemapped) { [weak self] _ in
            self?.scheduleRefresh()
        }

        if let browserBridge = engine.browserBridge {
            observe(browserBridge.$status) { [weak self] _ in
                self?.scheduleRefresh()
            }
        }
    }

    private func observe<P: Publisher>(
        _ publisher: P,
        receiveValue: @escaping (P.Output) -> Void
    ) where P.Failure == Never {
        publisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: receiveValue)
            .store(in: &cancellables)
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    private func refresh() {
        snapshot = SettingsSnapshot.live(
            engine: engine,
            versionBuild: versionBuild,
            shortcutConflicts: shortcutConflicts,
            adapters: sortedAdapters
        )
    }

    private static func sortedAdapters(_ adapters: [Adapter]) -> [Adapter] {
        adapters.sorted { lhs, rhs in
            let nameOrder = lhs.appName.localizedCaseInsensitiveCompare(rhs.appName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.appIdentifier < rhs.appIdentifier
        }
    }

    private static func bundleVersionBuild() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
}

enum SettingsTab: Hashable {
    case setup
    case shortcuts
    case adapters
    case advanced
}

struct SettingsSnapshot {
    let shortcuts: [CanonicalShortcut]
    let shortcutProfile: UserShortcutProfile
    let shortcutConflicts: [ShortcutConflict]
    let adapters: [Adapter]
    let validationMessages: [String]
    let adapterGenerationMessage: String?
    let generatedAdapterPreview: Adapter?
    let versionBuild: String
    let engineStatus: String
    let accessibilityStatus: String
    let browserBridgeStatus: String
    let safariExtensionStatus: SafariExtensionStatus
    let launchAtLoginStatus: LaunchAtLoginStatus
    let updateStatus: UpdateStatus
    let firstRunComplete: Bool
    let diagnostics: RuntimeDiagnosticSnapshot
    let displayStatus: EngineDisplayStatus
    let activeAppName: String
    let activeAvailability: ShortcutAvailability
    let isWaitingForAccessibilityPermission: Bool

    static func live(
        engine: ShortcutEngine,
        versionBuild: String,
        shortcutConflicts: [ShortcutConflict],
        adapters: [Adapter]
    ) -> SettingsSnapshot {
        let diagnostics = engine.diagnosticSnapshot()
        let appID = engine.appMonitor.effectiveAppID
        let activeAppName = Self.activeContextTitle(engine: engine, appID: appID)

        return SettingsSnapshot(
            shortcuts: engine.shortcutProfile.shortcuts,
            shortcutProfile: engine.shortcutProfile,
            shortcutConflicts: shortcutConflicts,
            adapters: adapters,
            validationMessages: engine.registry.validationMessages,
            adapterGenerationMessage: engine.adapterGenerationMessage,
            generatedAdapterPreview: engine.generatedAdapterPreview,
            versionBuild: versionBuild,
            engineStatus: engine.status.title,
            accessibilityStatus: ShortcutEngine.hasAccessibilityPermission ? "Granted" : "Not granted",
            browserBridgeStatus: engine.browserBridge?.status.title ?? "Unavailable",
            safariExtensionStatus: engine.safariExtensionStatus,
            launchAtLoginStatus: engine.launchAtLoginStatus,
            updateStatus: engine.updateStatus,
            firstRunComplete: engine.isFirstRunComplete,
            diagnostics: diagnostics,
            displayStatus: EngineDisplayStatus.make(
                status: engine.status,
                permissionState: engine.permissionState,
                eventTapEnabled: engine.eventTap.isEnabled,
                isWaitingForPermission: engine.isWaitingForAccessibilityPermission
            ),
            activeAppName: activeAppName,
            activeAvailability: engine.registry.availability(
                for: appID,
                displayName: activeAppName
            ),
            isWaitingForAccessibilityPermission: engine.isWaitingForAccessibilityPermission
        )
    }

    private static func activeContextTitle(
        engine: ShortcutEngine,
        appID: String?
    ) -> String {
        let appName = engine.appMonitor.currentAppName ?? "Unknown"
        guard let domain = engine.appMonitor.webAppDomain,
              let appID,
              appID.hasPrefix("web:")
        else {
            return appName
        }

        let adapterName = engine.registry.activeAdapter(for: appID)?.appName
            ?? DomainNormalizer.normalizedDomain(for: domain)
        return "\(adapterName) in \(appName)"
    }
}

struct SettingsActions {
    let openAccessibilitySettings: () -> Void
    let generateForActiveApp: () -> Void
    let saveGeneratedAdapter: () -> Void
    let discardGeneratedAdapter: () -> Void
    let markFirstRunComplete: () -> Void
    let resetFirstRun: () -> Void
    let setLaunchAtLogin: (Bool) -> Void
    let setAutomaticUpdates: (Bool) -> Void
    let checkForUpdates: () -> Void
    let openSafariExtensionSettings: () -> Void
    let exportSupportBundle: () -> Void

    static let noop = SettingsActions(
        openAccessibilitySettings: {},
        generateForActiveApp: {},
        saveGeneratedAdapter: {},
        discardGeneratedAdapter: {},
        markFirstRunComplete: {},
        resetFirstRun: {},
        setLaunchAtLogin: { _ in },
        setAutomaticUpdates: { _ in },
        checkForUpdates: {},
        openSafariExtensionSettings: {},
        exportSupportBundle: {}
    )

    static func live(engine: ShortcutEngine) -> SettingsActions {
        SettingsActions(
            openAccessibilitySettings: { engine.openAccessibilitySettings() },
            generateForActiveApp: { engine.generateAdapterForCurrentApp() },
            saveGeneratedAdapter: { engine.saveGeneratedAdapterPreview() },
            discardGeneratedAdapter: { engine.discardGeneratedAdapterPreview() },
            markFirstRunComplete: { engine.markFirstRunComplete() },
            resetFirstRun: { engine.resetFirstRunState() },
            setLaunchAtLogin: { engine.setLaunchAtLoginEnabled($0) },
            setAutomaticUpdates: { engine.setAutomaticUpdateChecksEnabled($0) },
            checkForUpdates: {
                engine.recordUpdateCheckResult(
                    state: .failed,
                    detail: "Sparkle is not bundled in this build yet; release packaging will enable this check."
                )
            },
            openSafariExtensionSettings: {
                SFSafariApplication.showPreferencesForExtension(
                    withIdentifier: engine.safariExtensionStatus.bundleIdentifier
                ) { error in
                    if let error {
                        DispatchQueue.main.async {
                            engine.setSafariExtensionStatus(
                                SafariExtensionStatus(
                                    state: .needsAttention,
                                    detail: "Could not open Safari extension settings: \(error.localizedDescription)"
                                )
                            )
                        }
                    }
                }
            },
            exportSupportBundle: {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "shorty-support.json"
                panel.allowedContentTypes = [.json]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try engine.exportSupportBundle(to: url)
                } catch {
                    engine.lastError = "Could not export support bundle: \(error.localizedDescription)"
                }
            }
        )
    }
}

struct SettingsContentView: View {
    let snapshot: SettingsSnapshot
    let actions: SettingsActions

    @State private var selectedTab: SettingsTab
    @State private var selectedCategory: CanonicalShortcut.Category?
    @State private var shortcutSearch = ""
    @State private var adapterSearch = ""

    private var canonicalByID: [String: CanonicalShortcut] {
        Dictionary(uniqueKeysWithValues: snapshot.shortcuts.map { ($0.id, $0) })
    }

    private var filteredShortcuts: [CanonicalShortcut] {
        let query = shortcutSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.shortcuts.filter { shortcut in
            let matchesCategory = selectedCategory == nil || shortcut.category == selectedCategory
            let matchesSearch = query.isEmpty
                || shortcut.name.localizedCaseInsensitiveContains(query)
                || shortcut.description.localizedCaseInsensitiveContains(query)
                || shortcut.id.localizedCaseInsensitiveContains(query)
            return matchesCategory && matchesSearch
        }
    }

    private var filteredAdapters: [Adapter] {
        let query = adapterSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeID = snapshot.activeAvailability.adapterIdentifier
        return snapshot.adapters
            .filter { adapter in
                query.isEmpty
                    || adapter.appName.localizedCaseInsensitiveContains(query)
                    || adapter.appIdentifier.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                if lhs.appIdentifier == activeID { return true }
                if rhs.appIdentifier == activeID { return false }
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
    }

    init(
        snapshot: SettingsSnapshot,
        actions: SettingsActions = .noop,
        initialTab: SettingsTab = .setup,
        initialCategory: CanonicalShortcut.Category? = .navigation
    ) {
        self.snapshot = snapshot
        self.actions = actions
        _selectedTab = State(initialValue: initialTab)
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SettingsSetupTab(
                snapshot: snapshot,
                actions: actions
            )
            .tabItem {
                Label("Setup", systemImage: "checklist")
            }
            .tag(SettingsTab.setup)

            SettingsShortcutsTab(
                selectedCategory: $selectedCategory,
                searchText: $shortcutSearch,
                shortcuts: filteredShortcuts,
                conflicts: snapshot.shortcutConflicts
            )
            .tabItem {
                Label("Shortcuts", systemImage: "command")
            }
            .tag(SettingsTab.shortcuts)

            SettingsAdaptersTab(
                searchText: $adapterSearch,
                adapters: filteredAdapters,
                validationMessages: snapshot.validationMessages,
                generationMessage: snapshot.adapterGenerationMessage,
                generatedPreview: snapshot.generatedAdapterPreview,
                canonicalByID: canonicalByID,
                activeAvailability: snapshot.activeAvailability,
                accessibilityGranted: snapshot.displayStatus.requiresPermission == false,
                actions: actions
            )
            .tabItem {
                Label("Apps", systemImage: "app.dashed")
            }
            .tag(SettingsTab.adapters)

            SettingsAdvancedTab(snapshot: snapshot, actions: actions)
            .tabItem {
                Label("Advanced", systemImage: "slider.horizontal.3")
            }
            .tag(SettingsTab.advanced)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 540, idealHeight: 620)
        .onAppear {
            if !snapshot.firstRunComplete {
                selectedTab = .setup
            }
        }
    }
}

private struct SettingsSetupTab: View {
    let snapshot: SettingsSnapshot
    let actions: SettingsActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ShortyPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Get Shorty ready")
                            .font(.headline)
                        Text("Shorty needs one macOS permission before it can translate shortcuts for the app in front.")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SetupPermissionRow(
                            status: snapshot.displayStatus,
                            actions: actions
                        )
                        SetupLaunchAtLoginRow(
                            status: snapshot.launchAtLoginStatus,
                            actions: actions
                        )
                        SetupChecklistRow(
                            title: "Ready state",
                            detail: snapshot.displayStatus.requiresPermission
                                ? "Shortcuts pass through until access is granted."
                                : "Accessibility access is granted.",
                            isComplete: !snapshot.displayStatus.requiresPermission
                        )

                        if !snapshot.firstRunComplete && !snapshot.displayStatus.requiresPermission {
                            Button("Done", action: actions.markFirstRunComplete)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }

                ShortyPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current app")
                            .font(.headline)
                        SettingsInfoRow("App", snapshot.activeAppName)
                        SettingsInfoRow("Coverage", snapshot.activeAvailability.coverageTitle)
                        Text(snapshot.activeAvailability.coverageDetail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
        }
    }
}

private struct SetupPermissionRow: View {
    let status: EngineDisplayStatus
    let actions: SettingsActions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility")
                        .fontWeight(.medium)
                    Text(status.requiresPermission ? status.detail : "Access granted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(
                    systemName: status.requiresPermission
                        ? "exclamationmark.circle.fill"
                        : "checkmark.circle.fill"
                )
                .foregroundColor(status.requiresPermission ? ShortyBrand.amber : ShortyBrand.teal)
            }

            Spacer()

            if status.requiresPermission {
                HStack(spacing: 8) {
                    Button("Open Settings", action: actions.openAccessibilitySettings)
                    if status.isWaitingForPermission {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

private struct SetupLaunchAtLoginRow: View {
    let status: LaunchAtLoginStatus
    let actions: SettingsActions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .fontWeight(.medium)
                    Text(status.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: status.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(status.isEnabled ? ShortyBrand.teal : .secondary)
            }

            Spacer()

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { status.isEnabled },
                    set: { actions.setLaunchAtLogin($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }
}

private struct SetupChecklistRow: View {
    let title: String
    let detail: String
    let isComplete: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } icon: {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isComplete ? ShortyBrand.teal : .secondary)
        }
    }
}

private struct SettingsShortcutsTab: View {
    @Binding var selectedCategory: CanonicalShortcut.Category?
    @Binding var searchText: String

    let shortcuts: [CanonicalShortcut]
    let conflicts: [ShortcutConflict]

    var body: some View {
        HSplitView {
            SettingsCategoryList(selectedCategory: $selectedCategory)
            SettingsShortcutList(
                searchText: $searchText,
                shortcuts: shortcuts,
                conflicts: conflicts
            )
        }
    }
}

private struct SettingsCategoryList: View {
    @Binding var selectedCategory: CanonicalShortcut.Category?

    var body: some View {
        List(
            CanonicalShortcut.Category.allCases,
            id: \.self,
            selection: $selectedCategory
        ) { category in
            Label(category.rawValue.capitalized, systemImage: iconFor(category))
        }
        .listStyle(.sidebar)
        .frame(minWidth: 150, maxWidth: 190)
    }
}

private struct SettingsShortcutList: View {
    @Binding var searchText: String

    let shortcuts: [CanonicalShortcut]
    let conflicts: [ShortcutConflict]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search shortcuts", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if !conflicts.isEmpty {
                Label(
                    "\(conflicts.count) shortcut review item\(conflicts.count == 1 ? "" : "s")",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundColor(ShortyBrand.amber)
            }

            List(shortcuts) { shortcut in
                SettingsShortcutRow(shortcut: shortcut)
            }
        }
        .padding()
    }
}

private struct SettingsAdvancedTab: View {
    let snapshot: SettingsSnapshot
    let actions: SettingsActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AdvancedBrowsersSection(
                    safariStatus: snapshot.safariExtensionStatus,
                    bridgeStatus: snapshot.browserBridgeStatus,
                    diagnostics: snapshot.diagnostics,
                    actions: actions
                )
                AdvancedUpdatesSection(
                    updateStatus: snapshot.updateStatus,
                    actions: actions
                )
                AdvancedDiagnosticsSection(
                    diagnostics: snapshot.diagnostics,
                    validationMessages: snapshot.validationMessages,
                    actions: actions
                )
                AdvancedSetupSection(
                    firstRunComplete: snapshot.firstRunComplete,
                    actions: actions
                )
                AdvancedAboutSection(
                    versionBuild: snapshot.versionBuild,
                    engineStatus: snapshot.engineStatus,
                    adapterCount: snapshot.adapters.count,
                    shortcutCount: snapshot.shortcuts.count,
                    accessibilityStatus: snapshot.accessibilityStatus,
                    browserBridgeStatus: snapshot.browserBridgeStatus,
                    updateStatus: snapshot.updateStatus
                )
            }
            .padding()
        }
    }
}

private struct AdvancedBrowsersSection: View {
    let safariStatus: SafariExtensionStatus
    let bridgeStatus: String
    let diagnostics: RuntimeDiagnosticSnapshot
    let actions: SettingsActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Browsers")
                    .font(.headline)
                SettingsInfoRow("Safari", safariStatus.title)
                Text(safariStatus.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Safari Extension Settings", action: actions.openSafariExtensionSettings)
                    .controlSize(.small)
                Divider()
                SettingsInfoRow("Chrome-family bridge", bridgeStatus)
                SettingsInfoRow("Browser source", diagnostics.browserContextSource.title)
                SettingsInfoRow("Web domain", diagnostics.webDomain ?? "None")
            }
        }
    }
}

private struct AdvancedUpdatesSection: View {
    let updateStatus: UpdateStatus
    let actions: SettingsActions

    @State private var automaticChecksEnabled: Bool

    init(updateStatus: UpdateStatus, actions: SettingsActions) {
        self.updateStatus = updateStatus
        self.actions = actions
        _automaticChecksEnabled = State(initialValue: updateStatus.automaticChecksEnabled)
    }

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Updates")
                    .font(.headline)
                Text(updateStatus.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Check for updates automatically", isOn: $automaticChecksEnabled)
                    .onChange(of: automaticChecksEnabled) { nextValue in
                        actions.setAutomaticUpdates(nextValue)
                    }
                SettingsInfoRow("Current version", updateStatus.currentVersion)
                SettingsInfoRow("Last checked", formatted(updateStatus.lastCheckedAt))
                if let sourceURL = updateStatus.sourceURL {
                    Link("Source and release notes", destination: sourceURL)
                }
                Text("Manual update checks will appear here when Sparkle is bundled.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return DateFormatter.localizedString(
            from: date,
            dateStyle: .medium,
            timeStyle: .short
        )
    }
}

private struct AdvancedDiagnosticsSection: View {
    let diagnostics: RuntimeDiagnosticSnapshot
    let validationMessages: [String]
    let actions: SettingsActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostics")
                    .font(.headline)
                SettingsInfoRow("Engine", diagnostics.engineStatus)
                SettingsInfoRow("Permission", diagnostics.permissionState.rawValue)
                SettingsInfoRow("Active app", diagnostics.currentAppName ?? "Unknown")
                SettingsInfoRow("Effective app", diagnostics.effectiveAppID ?? "None")
                SettingsInfoRow("Browser source", diagnostics.browserContextSource.title)
                SettingsInfoRow("Events intercepted", "\(diagnostics.eventsIntercepted)")
                SettingsInfoRow("Events translated", "\(diagnostics.eventsRemapped)")
                Button("Export Support Bundle", action: actions.exportSupportBundle)
                    .controlSize(.small)

                if !validationMessages.isEmpty {
                    Divider()
                    Label(
                        "\(validationMessages.count) adapter warning\(validationMessages.count == 1 ? "" : "s")",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundColor(ShortyBrand.amber)
                }
            }
        }
    }
}

private struct AdvancedSetupSection: View {
    let firstRunComplete: Bool
    let actions: SettingsActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup state")
                    .font(.headline)
                SettingsInfoRow(
                    "First-run setup",
                    firstRunComplete ? "Complete" : "Not complete"
                )
                Button("Reset Setup", action: actions.resetFirstRun)
                    .controlSize(.small)
            }
        }
    }
}

private struct AdvancedAboutSection: View {
    let versionBuild: String
    let engineStatus: String
    let adapterCount: Int
    let shortcutCount: Int
    let accessibilityStatus: String
    let browserBridgeStatus: String
    let updateStatus: UpdateStatus

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("About")
                    .font(.headline)
                SettingsInfoRow("Version", versionBuild)
                SettingsInfoRow("Engine", engineStatus)
                SettingsInfoRow("Adapters", "\(adapterCount)")
                SettingsInfoRow("Shortcuts", "\(shortcutCount)")
                SettingsInfoRow("Accessibility", accessibilityStatus)
                SettingsInfoRow("Browser bridge", browserBridgeStatus)
                Text("Shorty is free software under AGPL-3.0-or-later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    if let sourceURL = updateStatus.sourceURL {
                        Link("Source", destination: sourceURL)
                    }
                    if let licenseURL = OpenSourceLinks.license {
                        Link("License", destination: licenseURL)
                    }
                    if let supportURL = OpenSourceLinks.support {
                        Link("Support", destination: supportURL)
                    }
                    if let securityURL = OpenSourceLinks.security {
                        Link("Security", destination: securityURL)
                    }
                }
            }
        }
    }
}

private struct SettingsBrowsersTab: View {
    let safariStatus: SafariExtensionStatus
    let bridgeStatus: String
    let diagnostics: RuntimeDiagnosticSnapshot
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShortyPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Safari")
                        .font(.headline)
                    SettingsInfoRow("Status", safariStatus.title)
                    SettingsInfoRow("Extension ID", safariStatus.bundleIdentifier)
                    SettingsInfoRow("Last domain", safariStatus.lastDomain ?? "None")
                    Text(safariStatus.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Safari Extension Settings", action: actions.openSafariExtensionSettings)
                }
            }

            ShortyPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chrome-family bridge")
                        .font(.headline)
                    SettingsInfoRow("Status", bridgeStatus)
                    SettingsInfoRow("Browser source", diagnostics.browserContextSource.title)
                    SettingsInfoRow("Web domain", diagnostics.webDomain ?? "None")
                    Text("In-app install and uninstall will manage native messaging manifests for Chrome, Brave, Edge, Chromium, Vivaldi, and Chrome Canary.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
    }
}

private struct SettingsUpdatesTab: View {
    let updateStatus: UpdateStatus
    let actions: SettingsActions

    @State private var automaticChecksEnabled: Bool

    init(updateStatus: UpdateStatus, actions: SettingsActions) {
        self.updateStatus = updateStatus
        self.actions = actions
        _automaticChecksEnabled = State(initialValue: updateStatus.automaticChecksEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShortyPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text(updateStatus.title)
                        .font(.headline)
                    Text(updateStatus.detail)
                        .foregroundColor(.secondary)
                    Toggle("Check for updates automatically", isOn: $automaticChecksEnabled)
                        .onChange(of: automaticChecksEnabled) { nextValue in
                            actions.setAutomaticUpdates(nextValue)
                        }
                    SettingsInfoRow("Current version", updateStatus.currentVersion)
                    SettingsInfoRow("Last checked", formatted(updateStatus.lastCheckedAt))
                    if let sourceURL = updateStatus.sourceURL {
                        Link("Source and release notes", destination: sourceURL)
                    }
                    Button("Check for Updates", action: actions.checkForUpdates)
                }
            }
            Spacer()
        }
        .padding()
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return DateFormatter.localizedString(
            from: date,
            dateStyle: .medium,
            timeStyle: .short
        )
    }
}

private struct SettingsDiagnosticsTab: View {
    let diagnostics: RuntimeDiagnosticSnapshot
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShortyPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Runtime diagnostics")
                        .font(.headline)
                    SettingsInfoRow("Engine", diagnostics.engineStatus)
                    SettingsInfoRow("Permission", diagnostics.permissionState.rawValue)
                    SettingsInfoRow("Active app", diagnostics.currentAppName ?? "Unknown")
                    SettingsInfoRow("Effective app", diagnostics.effectiveAppID ?? "None")
                    SettingsInfoRow("Browser source", diagnostics.browserContextSource.title)
                    SettingsInfoRow("Events intercepted", "\(diagnostics.eventsIntercepted)")
                    SettingsInfoRow("Events remapped", "\(diagnostics.eventsRemapped)")
                    Button("Export Support Bundle", action: actions.exportSupportBundle)
                }
            }

            if !diagnostics.adapterValidationMessages.isEmpty {
                ShortyPanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Adapter warnings")
                            .font(.headline)
                        ForEach(diagnostics.adapterValidationMessages, id: \.self) { message in
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }
}

private struct SettingsShortcutRow: View {
    let shortcut: CanonicalShortcut

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(shortcut.name)
                    .fontWeight(.medium)
                Text(shortcut.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ShortcutKeyBadge(text: shortcut.defaultKeys.displayString)
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsAdaptersTab: View {
    @Binding var searchText: String

    let adapters: [Adapter]
    let validationMessages: [String]
    let generationMessage: String?
    let generatedPreview: Adapter?
    let canonicalByID: [String: CanonicalShortcut]
    let activeAvailability: ShortcutAvailability
    let accessibilityGranted: Bool
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ActiveAppCoveragePanel(
                availability: activeAvailability,
                accessibilityGranted: accessibilityGranted,
                actions: actions
            )

            AdapterGenerationPanel(
                message: generationMessage,
                preview: generatedPreview,
                canonicalByID: canonicalByID,
                accessibilityGranted: accessibilityGranted,
                actions: actions
            )

            TextField("Search apps", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(adapters) { adapter in
                SettingsAdapterRow(adapter: adapter, canonicalByID: canonicalByID)
            }

            if !validationMessages.isEmpty {
                Label(
                    "\(validationMessages.count) adapter file\(validationMessages.count == 1 ? "" : "s") need review.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundColor(ShortyBrand.amber)
            }
        }
        .padding()
    }
}

private struct ActiveAppCoveragePanel: View {
    let availability: ShortcutAvailability
    let accessibilityGranted: Bool
    let actions: SettingsActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current app")
                            .font(.headline)
                        Text(availability.appDisplayName)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(availability.coverageTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(availability.state == .available ? ShortyBrand.teal : .secondary)
                }

                Text(availability.coverageDetail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if availability.state == .noAdapter {
                    if accessibilityGranted {
                        Button("Add Current App", action: actions.generateForActiveApp)
                            .controlSize(.small)
                    } else {
                        Text("Grant Accessibility access before adding app support.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

private struct AdapterGenerationPanel: View {
    let message: String?
    let preview: Adapter?
    let canonicalByID: [String: CanonicalShortcut]
    let accessibilityGranted: Bool
    let actions: SettingsActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add Current App")
                            .font(.headline)
                        Text("Read the active app's menus, then review the shortcuts before saving.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if accessibilityGranted {
                        Button("Add Current App", action: actions.generateForActiveApp)
                    }
                }

                if !accessibilityGranted {
                    Label(
                        "Grant Accessibility access before adding app support.",
                        systemImage: "lock"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let preview {
                    DisclosureGroup("Generated preview for \(preview.appName)") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.mappings) { mapping in
                                Text("\(canonicalName(for: mapping.canonicalID)): \(mappingDetail(mapping))")
                                    .font(.caption)
                            }

                            HStack {
                                Button("Save Adapter", action: actions.saveGeneratedAdapter)
                                    .buttonStyle(.borderedProminent)

                                Button("Discard", action: actions.discardGeneratedAdapter)
                            }
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func canonicalName(for canonicalID: String) -> String {
        canonicalByID[canonicalID]?.name ?? canonicalID
    }
}

private struct SettingsAdapterRow: View {
    let adapter: Adapter
    let canonicalByID: [String: CanonicalShortcut]

    var body: some View {
        DisclosureGroup {
            ForEach(adapter.mappings) { mapping in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(canonicalName(for: mapping.canonicalID))
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(mappingDetail(mapping))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(mapping.method.rawValue)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 1)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(adapter.appName)
                        .fontWeight(.medium)
                    AdapterSourcePill(source: adapter.source)
                    Spacer()
                    Text("\(adapter.mappings.count) shortcuts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(adapter.appIdentifier)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            }
        }
    }

    private func canonicalName(for canonicalID: String) -> String {
        canonicalByID[canonicalID]?.name ?? canonicalID
    }
}

private struct AdapterSourcePill: View {
    let source: Adapter.Source

    var body: some View {
        Text(source.settingsLabel)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

private struct SettingsAboutTab: View {
    let versionBuild: String
    let engineStatus: String
    let adapterCount: Int
    let shortcutCount: Int
    let accessibilityStatus: String
    let browserBridgeStatus: String
    let updateStatus: UpdateStatus

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ShortyMarkView(size: 64)

                Text("Shorty")
                    .font(.title)
                    .fontWeight(.bold)

                Text("A local command map for macOS shortcuts.")
                    .foregroundColor(.secondary)

                Divider()

                ShortyPanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App")
                            .font(.headline)
                        SettingsInfoRow("Version", versionBuild)
                        SettingsInfoRow("Engine", engineStatus)
                        SettingsInfoRow("Adapters loaded", "\(adapterCount)")
                        SettingsInfoRow("Canonical shortcuts", "\(shortcutCount)")
                        SettingsInfoRow("Accessibility", accessibilityStatus)
                        SettingsInfoRow("Browser bridge", browserBridgeStatus)
                    }
                }

                ShortyPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Open Source")
                            .font(.headline)
                        Text("Shorty is free software under the GNU Affero General Public License, version 3 or later.")
                            .foregroundColor(.secondary)
                        SettingsInfoRow("SPDX", "AGPL-3.0-or-later")
                        SettingsInfoRow("Copyright", "Copyright (C) 2026 Peyton Randolph")
                        Text("Shorty is provided without warranty, including without the implied warranty of merchantability or fitness for a particular purpose.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            if let sourceURL = updateStatus.sourceURL {
                                Link("Source Code", destination: sourceURL)
                            }
                            if let licenseURL = OpenSourceLinks.license {
                                Link("License", destination: licenseURL)
                            }
                            if let supportURL = OpenSourceLinks.support {
                                Link("Support", destination: supportURL)
                            }
                            if let securityURL = OpenSourceLinks.security {
                                Link("Security", destination: securityURL)
                            }
                        }
                    }
                }

                ShortyPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Attributions")
                            .font(.headline)
                        AttributionRow(
                            title: "Runtime libraries",
                            detail: "No third-party runtime libraries are bundled in Shorty.app."
                        )
                        AttributionRow(
                            title: "System frameworks",
                            detail: "Apple frameworks are provided by macOS and the Xcode SDK."
                        )
                        AttributionRow(
                            title: "Development tools",
                            detail: "Tuist, SwiftLint, uv, pytest, ruff, hk, mise, Prettier, shellcheck, shfmt, actionlint, zizmor, rumdl, and pkl are used for development and validation but are not bundled into the app."
                        )
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
    }
}

private enum OpenSourceLinks {
    static let license = URL(string: "https://github.com/peyton/shorty/blob/master/LICENSE")
    static let support = URL(string: "mailto:shorty@peyton.app")
    static let security = URL(string: "mailto:shorty@peyton.app?subject=Shorty%20security")
}

private struct AttributionRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .fontWeight(.medium)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsInfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}

private func mappingDetail(_ mapping: Adapter.Mapping) -> String {
    switch mapping.method {
    case .keyRemap:
        if let nativeKeys = mapping.nativeKeys {
            return "Send \(nativeKeys.displayString)"
        }
        return "Missing native key combo"
    case .menuInvoke:
        if let title = mapping.menuTitle {
            return "Invoke menu item \"\(title)\""
        }
        return "Missing menu title"
    case .axAction:
        if let action = mapping.axAction {
            return "Perform \(action)"
        }
        return "Missing AX action"
    case .passthrough:
        return "Use the app's native shortcut"
    }
}

private func iconFor(_ category: CanonicalShortcut.Category) -> String {
    switch category {
    case .navigation:
        return "arrow.left.arrow.right"
    case .editing:
        return "pencil"
    case .tabs:
        return "square.on.square"
    case .windows:
        return "macwindow"
    case .search:
        return "magnifyingglass"
    case .media:
        return "play.circle"
    case .system:
        return "gear"
    }
}

private extension Adapter.Source {
    var settingsLabel: String {
        switch self {
        case .builtin:
            return "Built-in"
        case .menuIntrospection:
            return "Generated"
        case .llmGenerated:
            return "Generated"
        case .community:
            return "Community"
        case .user:
            return "User"
        }
    }
}
