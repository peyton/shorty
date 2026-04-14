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
        observe(engine.$bridgeInstallStatuses) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$isFirstRunComplete) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$generatedAdapterPreview) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$generatedAdapterReview) { [weak self] _ in
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

        observe(engine.eventTap.$counters) { [weak self] _ in
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
    let generatedAdapterReview: AdapterReview?
    let adapterRevisions: [AdapterRevision]
    let versionBuild: String
    let engineStatus: String
    let accessibilityStatus: String
    let browserBridgeStatus: String
    let bridgeInstallStatuses: [BridgeInstallStatus]
    let safariExtensionStatus: SafariExtensionStatus
    let launchAtLoginStatus: LaunchAtLoginStatus
    let updateStatus: UpdateStatus
    let firstRunComplete: Bool
    let globalPauseUntil: Date?
    let feedbackMessage: String?
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
        let appSnapshot = engine.appMonitor.snapshot()
        let appID = appSnapshot.effectiveAppID
        let activeAppName = Self.activeContextTitle(
            engine: engine,
            appSnapshot: appSnapshot
        )

        return SettingsSnapshot(
            shortcuts: engine.shortcutProfile.shortcuts,
            shortcutProfile: engine.shortcutProfile,
            shortcutConflicts: shortcutConflicts,
            adapters: adapters,
            validationMessages: engine.registry.validationMessages,
            adapterGenerationMessage: engine.adapterGenerationMessage,
            generatedAdapterPreview: engine.generatedAdapterPreview,
            generatedAdapterReview: engine.generatedAdapterReview,
            adapterRevisions: engine.adapterRevisions,
            versionBuild: versionBuild,
            engineStatus: engine.status.title,
            accessibilityStatus: ShortcutEngine.hasAccessibilityPermission ? "Granted" : "Not granted",
            browserBridgeStatus: engine.browserBridge?.status.title ?? "Unavailable",
            bridgeInstallStatuses: engine.bridgeInstallStatuses,
            safariExtensionStatus: engine.safariExtensionStatus,
            launchAtLoginStatus: engine.launchAtLoginStatus,
            updateStatus: engine.updateStatus,
            firstRunComplete: engine.isFirstRunComplete,
            globalPauseUntil: engine.globalPauseUntil,
            feedbackMessage: engine.settingsFeedbackMessage ?? engine.lastError,
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
        appSnapshot: AppMonitor.Snapshot
    ) -> String {
        let appName = appSnapshot.currentAppName ?? "Unknown"
        guard let domain = appSnapshot.webAppDomain,
              let appID = appSnapshot.effectiveAppID,
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
    let refreshStatuses: () -> Void
    let setShortcutEnabled: (String, Bool) -> Void
    let updateShortcut: (String, KeyCombo) -> Void
    let resetShortcut: (String) -> Void
    let setAdapterEnabled: (String, Bool) -> Void
    let setMappingEnabled: (String, String, Bool) -> Void
    let deleteAdapter: (String) -> Void
    let exportAdapter: (String) -> Void
    let importAdapter: () -> Void
    let pauseCurrentApp: () -> Void
    let resumeCurrentApp: () -> Void
    let pauseForDuration: (TimeInterval) -> Void
    let resumeGlobalPause: () -> Void
    let openSafariExtensionSettings: () -> Void
    let exportSupportBundle: () -> Void
    let copySupportBundle: () -> Void

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
        refreshStatuses: {},
        setShortcutEnabled: { _, _ in },
        updateShortcut: { _, _ in },
        resetShortcut: { _ in },
        setAdapterEnabled: { _, _ in },
        setMappingEnabled: { _, _, _ in },
        deleteAdapter: { _ in },
        exportAdapter: { _ in },
        importAdapter: {},
        pauseCurrentApp: {},
        resumeCurrentApp: {},
        pauseForDuration: { _ in },
        resumeGlobalPause: {},
        openSafariExtensionSettings: {},
        exportSupportBundle: {},
        copySupportBundle: {}
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
            checkForUpdates: { engine.checkForUpdates() },
            refreshStatuses: { engine.refreshDailyStatuses() },
            setShortcutEnabled: { engine.setShortcut($0, enabled: $1) },
            updateShortcut: { engine.updateShortcut($0, keyCombo: $1) },
            resetShortcut: { engine.resetShortcut($0) },
            setAdapterEnabled: { engine.setAdapter($0, enabled: $1) },
            setMappingEnabled: {
                engine.setMapping(adapterID: $0, canonicalID: $1, enabled: $2)
            },
            deleteAdapter: { engine.deleteAdapter(appIdentifier: $0) },
            exportAdapter: { appIdentifier in
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "\(appIdentifier.replacingOccurrences(of: ":", with: "_")).json"
                panel.allowedContentTypes = [.json]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                do {
                    try engine.exportAdapter(appIdentifier: appIdentifier, to: url)
                } catch {
                    engine.lastError = "Could not export adapter: \(error.localizedDescription)"
                }
            },
            importAdapter: {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url else { return }
                engine.importAdapter(from: url)
            },
            pauseCurrentApp: { engine.pauseCurrentApp() },
            resumeCurrentApp: { engine.resumeCurrentApp() },
            pauseForDuration: { engine.pauseForDuration($0) },
            resumeGlobalPause: { engine.resumeGlobalPause() },
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
            },
            copySupportBundle: {
                do {
                    let data = try engine.supportBundle().encodedJSON()
                    guard let json = String(data: data, encoding: .utf8) else {
                        engine.lastError = "Could not encode support bundle as text."
                        return
                    }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(json, forType: .string)
                } catch {
                    engine.lastError = "Could not copy support bundle: \(error.localizedDescription)"
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
                    || adapter.mappings.contains { mapping in
                        mapping.canonicalID.localizedCaseInsensitiveContains(query)
                            || (mapping.nativeKeys?.description.localizedCaseInsensitiveContains(query) ?? false)
                            || (mapping.nativeKeys?.displayString.localizedCaseInsensitiveContains(query) ?? false)
                            || (mapping.menuTitle?.localizedCaseInsensitiveContains(query) ?? false)
                    }
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
        initialCategory: CanonicalShortcut.Category? = nil
    ) {
        self.snapshot = snapshot
        self.actions = actions
        _selectedTab = State(initialValue: initialTab)
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let feedback = snapshot.feedbackMessage, !feedback.isEmpty {
                SettingsFeedbackBanner(message: feedback)
            }

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
                    profile: snapshot.shortcutProfile,
                    conflicts: snapshot.shortcutConflicts,
                    actions: actions
                )
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(SettingsTab.shortcuts)

                SettingsAdaptersTab(
                    searchText: $adapterSearch,
                    adapters: filteredAdapters,
                    profile: snapshot.shortcutProfile,
                    validationMessages: snapshot.validationMessages,
                    generationMessage: snapshot.adapterGenerationMessage,
                    generatedPreview: snapshot.generatedAdapterPreview,
                    generatedReview: snapshot.generatedAdapterReview,
                    adapterRevisions: snapshot.adapterRevisions,
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
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 540, idealHeight: 620)
        .onAppear {
            actions.refreshStatuses()
            if snapshot.generatedAdapterPreview != nil {
                selectedTab = .adapters
            } else if !snapshot.firstRunComplete {
                selectedTab = .setup
            }
        }
    }
}

private struct SettingsFeedbackBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundColor(ShortyBrand.teal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(ShortyBrand.teal.opacity(0.08))
            .accessibilityIdentifier("settings-feedback")
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
    let profile: UserShortcutProfile
    let conflicts: [ShortcutConflict]
    let actions: SettingsActions

    var body: some View {
        HSplitView {
            SettingsCategoryList(selectedCategory: $selectedCategory)
            SettingsShortcutList(
                searchText: $searchText,
                shortcuts: shortcuts,
                profile: profile,
                conflicts: conflicts,
                actions: actions
            )
        }
    }
}

private struct SettingsCategoryList: View {
    @Binding var selectedCategory: CanonicalShortcut.Category?

    var body: some View {
        List(selection: $selectedCategory) {
            Label("All Shortcuts", systemImage: "keyboard")
                .tag(CanonicalShortcut.Category?.none)

            ForEach(CanonicalShortcut.Category.allCases, id: \.self) { category in
                Label(category.rawValue.capitalized, systemImage: iconFor(category))
                    .tag(CanonicalShortcut.Category?.some(category))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 150, maxWidth: 190)
    }
}

private struct SettingsShortcutList: View {
    @Binding var searchText: String

    let shortcuts: [CanonicalShortcut]
    let profile: UserShortcutProfile
    let conflicts: [ShortcutConflict]
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search shortcuts", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if !conflicts.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(conflicts) { conflict in
                            ShortcutConflictRow(conflict: conflict)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label(
                        "\(conflicts.count) shortcut review item\(conflicts.count == 1 ? "" : "s")",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundColor(ShortyBrand.amber)
                }
                .font(.caption)
            }

            if shortcuts.isEmpty {
                EmptySettingsState(
                    title: "No shortcuts found",
                    detail: "Try a different search or choose All Shortcuts."
                )
                Spacer()
            } else {
                List(shortcuts) { shortcut in
                    SettingsShortcutRow(
                        shortcut: shortcut,
                        isEnabled: profile.isShortcutEnabled(shortcut.id),
                        actions: actions
                    )
                }
            }
        }
        .padding()
    }
}

private struct ShortcutConflictRow: View {
    let conflict: ShortcutConflict

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conflict.message)
                .fontWeight(.medium)
            Text("Shortcuts: \(conflict.shortcutIDs.joined(separator: ", "))")
                .foregroundColor(.secondary)
            if let keyCombo = conflict.keyCombo {
                Text("Keys: \(keyCombo.displayString)")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    bridgeInstallStatuses: snapshot.bridgeInstallStatuses,
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
                    globalPauseUntil: snapshot.globalPauseUntil,
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
    let bridgeInstallStatuses: [BridgeInstallStatus]
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
                BridgeInstallStatusList(statuses: bridgeInstallStatuses)
                BridgeInstallCommandPanel()
            }
        }
    }
}

private struct AdvancedUpdatesSection: View {
    let updateStatus: UpdateStatus
    let actions: SettingsActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text("Updates")
                    .font(.headline)
                Text(updateStatus.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(
                    "Check for updates automatically",
                    isOn: Binding(
                        get: { updateStatus.automaticChecksEnabled },
                        set: { actions.setAutomaticUpdates($0) }
                    )
                )
                SettingsInfoRow("Current version", updateStatus.currentVersion)
                SettingsInfoRow("Last checked", formatted(updateStatus.lastCheckedAt))
                Button("Check for Updates", action: actions.checkForUpdates)
                    .controlSize(.small)
                if let sourceURL = updateStatus.sourceURL {
                    Link("Source and release notes", destination: sourceURL)
                }
                Text("Direct-download update checks will use the signed release feed when Sparkle is bundled.")
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

private struct BridgeInstallCommandPanel: View {
    @State private var extensionID = ""
    @State private var copiedMessage: String?

    private var normalizedExtensionID: String {
        extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidExtensionID: Bool {
        let id = normalizedExtensionID
        return id.range(of: #"^[a-z]{32}$"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Bridge commands")
                .font(.caption.weight(.semibold))
            TextField("Chrome extension ID", text: $extensionID)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            if !normalizedExtensionID.isEmpty && !isValidExtensionID {
                Text("Chrome extension IDs are 32 lowercase letters.")
                    .font(.caption2)
                    .foregroundColor(ShortyBrand.amber)
            }
            HStack {
                Button("Copy Install Command") {
                    copy("just install-browser-bridge EXTENSION_ID=\(normalizedExtensionID) BROWSERS=chrome,brave,edge")
                }
                .disabled(!isValidExtensionID)

                Button("Copy Uninstall Command") {
                    copy("just uninstall-browser-bridge BROWSERS=chrome,brave,edge")
                }
            }
            .controlSize(.small)
            if let copiedMessage {
                Text(copiedMessage)
                    .font(.caption2)
                    .foregroundColor(ShortyBrand.teal)
            }
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedMessage = "Copied command."
    }
}

private struct BridgeInstallStatusList: View {
    let statuses: [BridgeInstallStatus]

    private var visibleStatuses: [BridgeInstallStatus] {
        statuses.filter { $0.browser != .safari }
    }

    var body: some View {
        if !visibleStatuses.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Native messaging manifests")
                    .font(.caption.weight(.semibold))
                ForEach(visibleStatuses) { status in
                    BridgeInstallStatusRow(status: status)
                }
                Text("Install or remove manifests with `just install-browser-bridge` and `just uninstall-browser-bridge` from a checkout. Shorty only reports status here.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct BridgeInstallStatusRow: View {
    let status: BridgeInstallStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(status.browser.displayName, systemImage: iconName)
                    .font(.caption)
                    .foregroundColor(iconColor)
                Spacer()
                Text(stateTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(iconColor)
            }
            Text(status.detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let manifestPath = status.manifestPath {
                Text(manifestPath)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private var stateTitle: String {
        switch status.state {
        case .installed:
            return "Installed"
        case .notInstalled:
            return "Not installed"
        case .needsAttention:
            return "Needs attention"
        case .unsupported:
            return "Unsupported"
        }
    }

    private var iconName: String {
        switch status.state {
        case .installed:
            return "checkmark.circle.fill"
        case .needsAttention:
            return "exclamationmark.triangle.fill"
        case .notInstalled, .unsupported:
            return "circle"
        }
    }

    private var iconColor: Color {
        switch status.state {
        case .installed:
            return ShortyBrand.teal
        case .needsAttention:
            return ShortyBrand.amber
        case .notInstalled, .unsupported:
            return .secondary
        }
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
                SettingsInfoRow("Key events seen", "\(diagnostics.eventsIntercepted)")
                SettingsInfoRow("Shortcuts matched", "\(diagnostics.eventsMatched)")
                SettingsInfoRow("Key remaps", "\(diagnostics.eventsRemapped)")
                SettingsInfoRow("Native pass-throughs", "\(diagnostics.eventsPassedThrough)")
                SettingsInfoRow("Menu actions", "\(diagnostics.menuActionsInvoked)")
                SettingsInfoRow("Menu succeeded", "\(diagnostics.menuActionsSucceeded)")
                SettingsInfoRow("Menu failed", "\(diagnostics.menuActionsFailed)")
                SettingsInfoRow("Accessibility actions", "\(diagnostics.accessibilityActionsInvoked)")
                SettingsInfoRow("Accessibility succeeded", "\(diagnostics.accessibilityActionsSucceeded)")
                SettingsInfoRow("Accessibility failed", "\(diagnostics.accessibilityActionsFailed)")
                SettingsInfoRow("Context guards", "\(diagnostics.contextGuardsApplied)")
                SettingsInfoRow("Distribution", diagnostics.distributionMode)
                if let action = diagnostics.lastAction {
                    SettingsInfoRow("Last action", "\(action.canonicalID): \(action.detail)")
                }
                HStack {
                    Button("Export Support Bundle", action: actions.exportSupportBundle)
                    Button("Copy Diagnostics", action: actions.copySupportBundle)
                }
                .controlSize(.small)

                if !validationMessages.isEmpty {
                    Divider()
                    AdapterValidationWarnings(messages: validationMessages)
                }
            }
        }
    }
}

private struct AdvancedSetupSection: View {
    let firstRunComplete: Bool
    let globalPauseUntil: Date?
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
                SettingsInfoRow("Global pause", globalPauseText)
                HStack {
                    Button("Pause 15 Minutes") {
                        actions.pauseForDuration(15 * 60)
                    }
                    Button("Pause Until Tomorrow") {
                        actions.pauseForDuration(24 * 60 * 60)
                    }
                    Button("Resume", action: actions.resumeGlobalPause)
                        .disabled(globalPauseUntil == nil)
                    Button("Reset Setup", action: actions.resetFirstRun)
                }
                .controlSize(.small)
            }
        }
    }

    private var globalPauseText: String {
        guard let globalPauseUntil else { return "Off" }
        return DateFormatter.localizedString(
            from: globalPauseUntil,
            dateStyle: .none,
            timeStyle: .short
        )
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

private struct SettingsShortcutRow: View {
    let shortcut: CanonicalShortcut
    let isEnabled: Bool
    let actions: SettingsActions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(
                "Enable \(shortcut.name)",
                isOn: Binding(
                    get: { isEnabled },
                    set: { actions.setShortcutEnabled(shortcut.id, $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                Text(shortcut.name)
                    .fontWeight(.medium)
                Text(shortcut.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(shortcut.category.rawValue.capitalized)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1), in: Capsule())
            ShortcutKeyBadge(text: shortcut.defaultKeys.displayString)
            ShortcutCaptureButton(shortcut: shortcut, actions: actions)
            Button("Reset") {
                actions.resetShortcut(shortcut.id)
            }
            .controlSize(.small)
        }
        .opacity(isEnabled ? 1 : 0.55)
        .padding(.vertical, 2)
        .accessibilityIdentifier("shortcut-row-\(shortcut.id)")
    }
}

private struct ShortcutCaptureButton: View {
    let shortcut: CanonicalShortcut
    let actions: SettingsActions

    @State private var capture = ShortcutCaptureResult(
        state: .idle,
        message: "Ready"
    )
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button(buttonTitle, action: toggleCapture)
                .controlSize(.small)
                .help(captureHelp)
                .accessibilityIdentifier("capture-\(shortcut.id)")
            if capture.state == .captured {
                Text(capture.layout.localizedName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var buttonTitle: String {
        switch capture.state {
        case .recording:
            return "Press keys..."
        case .captured:
            return "Captured"
        case .invalid:
            return "Try Again"
        case .idle, .cancelled:
            return "Capture"
        }
    }

    private var captureHelp: String {
        guard capture.state == .captured else {
            return capture.message
        }
        return "\(capture.message) Keyboard layout: \(capture.layout.localizedName)."
    }

    private func toggleCapture() {
        if capture.state == .recording {
            stopCapture(state: .cancelled, combo: nil, message: "Capture cancelled.")
            return
        }

        capture = ShortcutCaptureResult(
            state: .recording,
            message: "Press the shortcut to use for \(shortcut.name)."
        )
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = KeyCombo.Modifiers(eventModifierFlags: event.modifierFlags)
            guard event.keyCode > 0 || !modifiers.isEmpty else {
                stopCapture(
                    state: .invalid,
                    combo: nil,
                    message: "Press a key with optional modifiers."
                )
                return nil
            }
            let combo = KeyCombo(keyCode: UInt16(event.keyCode), modifiers: modifiers)
            actions.updateShortcut(shortcut.id, combo)
            stopCapture(
                state: .captured,
                combo: combo,
                layout: .current(),
                message: "Captured \(combo.displayString)."
            )
            return nil
        }
    }

    private func stopCapture(
        state: ShortcutCaptureResult.State,
        combo: KeyCombo?,
        layout: KeyboardLayoutDescriptor = .current(),
        message: String
    ) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        capture = ShortcutCaptureResult(
            state: state,
            keyCombo: combo,
            layout: layout,
            message: message
        )
    }
}

private struct SettingsAdaptersTab: View {
    @Binding var searchText: String

    let adapters: [Adapter]
    let profile: UserShortcutProfile
    let validationMessages: [String]
    let generationMessage: String?
    let generatedPreview: Adapter?
    let generatedReview: AdapterReview?
    let adapterRevisions: [AdapterRevision]
    let canonicalByID: [String: CanonicalShortcut]
    let activeAvailability: ShortcutAvailability
    let accessibilityGranted: Bool
    let actions: SettingsActions

    private var adapterSourceCounts: [(source: Adapter.Source, count: Int)] {
        Dictionary(grouping: adapters, by: \.source)
            .map { (source: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.source.sortOrder != rhs.source.sortOrder {
                    return lhs.source.sortOrder < rhs.source.sortOrder
                }
                return lhs.source.rawValue < rhs.source.rawValue
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ActiveAppCoveragePanel(
                availability: activeAvailability,
                accessibilityGranted: accessibilityGranted,
                actions: actions
            )

            if let caveat = AppCaveatsPanel.caveat(for: activeAvailability) {
                AppCaveatsPanel(caveat: caveat)
            }

            AdapterGenerationPanel(
                message: generationMessage,
                preview: generatedPreview,
                review: generatedReview,
                canonicalByID: canonicalByID,
                accessibilityGranted: accessibilityGranted,
                actions: actions
            )

            HStack {
                TextField("Search apps, bundle IDs, shortcuts, or key combos", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button("Import Adapter", action: actions.importAdapter)
                    .controlSize(.small)
            }

            AdapterSourceSummary(counts: adapterSourceCounts)

            if adapters.isEmpty {
                EmptySettingsState(
                    title: "No apps found",
                    detail: "Try a different search or add support for the current app."
                )
                Spacer()
            } else {
                List(adapters) { adapter in
                    SettingsAdapterRow(
                        adapter: adapter,
                        profile: profile,
                        canonicalByID: canonicalByID,
                        actions: actions
                    )
                }
            }

            if !validationMessages.isEmpty {
                AdapterValidationWarnings(messages: validationMessages)
            }

            if !adapterRevisions.isEmpty {
                AdapterRevisionHistory(revisions: adapterRevisions)
            }
        }
        .padding()
    }
}

private struct AdapterRevisionHistory: View {
    let revisions: [AdapterRevision]

    var body: some View {
        DisclosureGroup("Recent adapter saves") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(revisions.prefix(8))) { revision in
                    SettingsInfoRow(
                        revision.adapter.appName,
                        "\(revision.summary) \(formatted(revision.createdAt))"
                    )
                }
            }
            .padding(.top, 4)
        }
        .font(.caption)
    }

    private func formatted(_ date: Date) -> String {
        DateFormatter.localizedString(
            from: date,
            dateStyle: .none,
            timeStyle: .short
        )
    }
}

private struct AppCaveatsPanel: View {
    struct Caveat {
        let title: String
        let detail: String
    }

    let caveat: Caveat

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(caveat.title)
                    .font(.caption.weight(.semibold))
                Text(caveat.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } icon: {
            Image(systemName: "info.circle")
                .foregroundColor(ShortyBrand.amber)
        }
        .padding(.vertical, 2)
    }

    static func caveat(for availability: ShortcutAvailability) -> Caveat? {
        let id = availability.appIdentifier ?? ""
        if id.contains("Terminal") || id.contains("iterm") || id.contains("ghostty") {
            return Caveat(
                title: "Terminal shortcuts are conservative",
                detail: "Shorty avoids remapping text-entry and shell-control keys unless an adapter is explicit."
            )
        }
        if id.hasPrefix("web:") {
            return Caveat(
                title: "Web app context depends on the browser bridge",
                detail: "If the browser extension stops reporting domains, Shorty falls back to the browser's native shortcuts."
            )
        }
        if id.localizedCaseInsensitiveContains("password")
            || availability.appDisplayName.localizedCaseInsensitiveContains("password") {
            return Caveat(
                title: "Password managers stay hands-off",
                detail: "Use app-specific toggles to pause Shorty when handling credentials or secure fields."
            )
        }
        return nil
    }
}

private struct AdapterSourceSummary: View {
    let counts: [(source: Adapter.Source, count: Int)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(counts, id: \.source) { item in
                Text("\(item.source.settingsLabel): \(item.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            counts
                .map { "\($0.source.settingsLabel) \($0.count)" }
                .joined(separator: ", ")
        )
    }
}

private struct AdapterValidationWarnings: View {
    let messages: [String]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(messages, id: \.self) { message in
                    Text(message)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 4)
        } label: {
            Label(
                "\(messages.count) adapter file\(messages.count == 1 ? "" : "s") need review.",
                systemImage: "exclamationmark.triangle"
            )
        }
        .font(.caption)
        .foregroundColor(ShortyBrand.amber)
    }
}

private struct EmptySettingsState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
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

                HStack(spacing: 8) {
                    if availability.state == .available {
                        Button("Pause This App", action: actions.pauseCurrentApp)
                            .controlSize(.small)
                    }
                    if availability.state == .paused {
                        Button("Resume This App", action: actions.resumeCurrentApp)
                            .controlSize(.small)
                    }
                }

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
    let review: AdapterReview?
    let canonicalByID: [String: CanonicalShortcut]
    let accessibilityGranted: Bool
    let actions: SettingsActions

    @State private var approveRiskyGeneratedAdapter = false

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
                            if let review {
                                AdapterReviewSummary(review: review)
                            }

                            ForEach(preview.mappings) { mapping in
                                Text("\(canonicalName(for: mapping.canonicalID)): \(mappingDetail(mapping))")
                                    .font(.caption)
                            }

                            HStack {
                                Button("Save Adapter", action: actions.saveGeneratedAdapter)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(review?.requiresExplicitApproval == true && !approveRiskyGeneratedAdapter)

                                Button("Discard", action: actions.discardGeneratedAdapter)
                            }
                            .controlSize(.small)

                            if review?.requiresExplicitApproval == true {
                                Toggle(
                                    "I reviewed the warnings for text-entry or low-confidence mappings.",
                                    isOn: $approveRiskyGeneratedAdapter
                                )
                                .font(.caption2)
                                .toggleStyle(.checkbox)
                            }
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

private struct AdapterReviewSummary: View {
    let review: AdapterReview

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Review confidence")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(confidenceText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(confidenceColor)
            }

            ForEach(review.reasons, id: \.self) { reason in
                Label(reason, systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            ForEach(review.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundColor(ShortyBrand.amber)
            }
        }
        .padding(.vertical, 4)
    }

    private var confidenceText: String {
        "\(Int((review.confidence * 100).rounded()))%"
    }

    private var confidenceColor: Color {
        if review.confidence >= 0.75 {
            return ShortyBrand.teal
        }
        if review.confidence >= 0.5 {
            return ShortyBrand.amber
        }
        return .secondary
    }
}

private struct SettingsAdapterRow: View {
    let adapter: Adapter
    let profile: UserShortcutProfile
    let canonicalByID: [String: CanonicalShortcut]
    let actions: SettingsActions

    var body: some View {
        DisclosureGroup {
            HStack {
                Toggle(
                    "Enable \(adapter.appName)",
                    isOn: Binding(
                        get: { profile.isAdapterEnabled(adapter.appIdentifier) },
                        set: { actions.setAdapterEnabled(adapter.appIdentifier, $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
                if adapter.source != .builtin {
                    Button("Export") {
                        actions.exportAdapter(adapter.appIdentifier)
                    }
                    Button("Delete") {
                        actions.deleteAdapter(adapter.appIdentifier)
                    }
                }
            }
            .font(.caption)

            ForEach(adapter.mappings) { mapping in
                HStack(alignment: .firstTextBaseline) {
                    Toggle(
                        "Enable \(canonicalName(for: mapping.canonicalID))",
                        isOn: Binding(
                            get: {
                                mapping.isEnabled && profile.isMappingEnabled(
                                    adapterID: adapter.appIdentifier,
                                    canonicalID: mapping.canonicalID
                                )
                            },
                            set: {
                                actions.setMappingEnabled(
                                    adapter.appIdentifier,
                                    mapping.canonicalID,
                                    $0
                                )
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

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
                .opacity(mapping.isEnabled ? 1 : 0.5)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(adapter.appName)
                        .fontWeight(.medium)
                    AdapterSourcePill(source: adapter.source)
                    if !profile.isAdapterEnabled(adapter.appIdentifier) {
                        Text("Paused")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(ShortyBrand.amber)
                    }
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

private enum OpenSourceLinks {
    static let license = URL(string: "https://github.com/peyton/shorty/blob/master/LICENSE")
    static let support = URL(string: "mailto:shorty@peyton.app")
    static let security = URL(string: "mailto:shorty@peyton.app?subject=Shorty%20security")
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

private extension KeyCombo.Modifiers {
    init(eventModifierFlags: NSEvent.ModifierFlags) {
        var modifiers: KeyCombo.Modifiers = []
        if eventModifierFlags.contains(.command) { modifiers.insert(.command) }
        if eventModifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if eventModifierFlags.contains(.option) { modifiers.insert(.option) }
        if eventModifierFlags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}

private func mappingDetail(_ mapping: Adapter.Mapping) -> String {
    let suffix = mapping.matchReason.map { " · \($0)" } ?? ""
    switch mapping.method {
    case .keyRemap:
        if let nativeKeys = mapping.nativeKeys {
            return "Send \(nativeKeys.displayString)\(suffix)"
        }
        return "Missing native key combo"
    case .menuInvoke:
        if let path = mapping.menuPath, !path.isEmpty {
            return "Invoke \(path.joined(separator: " > "))\(suffix)"
        }
        if let title = mapping.menuTitle {
            return "Invoke menu item \"\(title)\"\(suffix)"
        }
        return "Missing menu title"
    case .axAction:
        if let action = mapping.axAction {
            return "Perform \(action)\(suffix)"
        }
        return "Missing AX action"
    case .passthrough:
        return "Use the app's native shortcut\(suffix)"
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
    var sortOrder: Int {
        switch self {
        case .builtin:
            return 0
        case .menuIntrospection, .llmGenerated:
            return 1
        case .community:
            return 2
        case .user:
            return 3
        }
    }

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
