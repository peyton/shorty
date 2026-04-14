import AppKit
import SafariServices
import ShortyCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var engine: ShortcutEngine

    var body: some View {
        SettingsContentView(
            snapshot: .live(engine: engine),
            actions: .live(engine: engine)
        )
    }
}

enum SettingsTab: Hashable {
    case setup
    case shortcuts
    case adapters
    case browsers
    case updates
    case diagnostics
    case about
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
    let updateStatus: UpdateStatus
    let firstRunComplete: Bool
    let diagnostics: RuntimeDiagnosticSnapshot

    static func live(engine: ShortcutEngine) -> SettingsSnapshot {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        let diagnostics = engine.diagnosticSnapshot()

        return SettingsSnapshot(
            shortcuts: engine.shortcutProfile.shortcuts,
            shortcutProfile: engine.shortcutProfile,
            shortcutConflicts: engine.shortcutProfile.conflicts(),
            adapters: engine.registry.allAdapters,
            validationMessages: engine.registry.validationMessages,
            adapterGenerationMessage: engine.adapterGenerationMessage,
            generatedAdapterPreview: engine.generatedAdapterPreview,
            versionBuild: "\(version) (\(build))",
            engineStatus: engine.status.title,
            accessibilityStatus: ShortcutEngine.hasAccessibilityPermission ? "Granted" : "Not granted",
            browserBridgeStatus: engine.browserBridge?.status.title ?? "Unavailable",
            safariExtensionStatus: engine.safariExtensionStatus,
            updateStatus: engine.updateStatus,
            firstRunComplete: engine.isFirstRunComplete,
            diagnostics: diagnostics
        )
    }
}

struct SettingsActions {
    let generateForActiveApp: () -> Void
    let saveGeneratedAdapter: () -> Void
    let discardGeneratedAdapter: () -> Void
    let markFirstRunComplete: () -> Void
    let resetFirstRun: () -> Void
    let setAutomaticUpdates: (Bool) -> Void
    let checkForUpdates: () -> Void
    let openSafariExtensionSettings: () -> Void
    let exportSupportBundle: () -> Void

    static let noop = SettingsActions(
        generateForActiveApp: {},
        saveGeneratedAdapter: {},
        discardGeneratedAdapter: {},
        markFirstRunComplete: {},
        resetFirstRun: {},
        setAutomaticUpdates: { _ in },
        checkForUpdates: {},
        openSafariExtensionSettings: {},
        exportSupportBundle: {}
    )

    static func live(engine: ShortcutEngine) -> SettingsActions {
        SettingsActions(
            generateForActiveApp: { engine.generateAdapterForCurrentApp() },
            saveGeneratedAdapter: { engine.saveGeneratedAdapterPreview() },
            discardGeneratedAdapter: { engine.discardGeneratedAdapterPreview() },
            markFirstRunComplete: { engine.markFirstRunComplete() },
            resetFirstRun: { engine.resetFirstRunState() },
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
        return snapshot.adapters
            .filter { adapter in
                query.isEmpty
                    || adapter.appName.localizedCaseInsensitiveContains(query)
                    || adapter.appIdentifier.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.appName < $1.appName }
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
                actions: actions
            )
            .tabItem {
                Label("Apps", systemImage: "app.dashed")
            }
            .tag(SettingsTab.adapters)

            SettingsBrowsersTab(
                safariStatus: snapshot.safariExtensionStatus,
                bridgeStatus: snapshot.browserBridgeStatus,
                diagnostics: snapshot.diagnostics,
                actions: actions
            )
            .tabItem {
                Label("Browsers", systemImage: "safari")
            }
            .tag(SettingsTab.browsers)

            SettingsUpdatesTab(
                updateStatus: snapshot.updateStatus,
                actions: actions
            )
            .tabItem {
                Label("Updates", systemImage: "arrow.down.circle")
            }
            .tag(SettingsTab.updates)

            SettingsDiagnosticsTab(
                diagnostics: snapshot.diagnostics,
                actions: actions
            )
            .tabItem {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
            }
            .tag(SettingsTab.diagnostics)

            SettingsAboutTab(
                versionBuild: snapshot.versionBuild,
                engineStatus: snapshot.engineStatus,
                adapterCount: snapshot.adapters.count,
                shortcutCount: snapshot.shortcuts.count,
                accessibilityStatus: snapshot.accessibilityStatus,
                browserBridgeStatus: snapshot.browserBridgeStatus,
                updateStatus: snapshot.updateStatus
            )
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
            .tag(SettingsTab.about)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 540, idealHeight: 620)
    }
}

private struct SettingsSetupTab: View {
    let snapshot: SettingsSnapshot
    let actions: SettingsActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ShortyPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Release setup")
                            .font(.headline)
                        Text("Finish the local checks that make Shorty safe to leave running every day.")
                            .foregroundColor(.secondary)
                        SetupChecklistRow(
                            title: "Accessibility",
                            detail: "Required for shortcut translation and menu adapter generation.",
                            isComplete: snapshot.accessibilityStatus == "Granted"
                        )
                        SetupChecklistRow(
                            title: "Safari extension",
                            detail: snapshot.safariExtensionStatus.detail,
                            isComplete: snapshot.safariExtensionStatus.state == .enabled
                        )
                        SetupChecklistRow(
                            title: "Browser bridge",
                            detail: snapshot.browserBridgeStatus,
                            isComplete: snapshot.browserBridgeStatus.contains("ready")
                                || snapshot.browserBridgeStatus.contains("connected")
                        )
                        SetupChecklistRow(
                            title: "First-run review",
                            detail: snapshot.firstRunComplete ? "Marked complete." : "Review setup before relying on remapping.",
                            isComplete: snapshot.firstRunComplete
                        )
                        HStack {
                            Button("Mark Setup Complete", action: actions.markFirstRunComplete)
                                .buttonStyle(.borderedProminent)
                            Button("Reset Setup", action: actions.resetFirstRun)
                        }
                    }
                }
            }
            .padding()
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
            ShortcutKeyBadge(text: shortcut.defaultKeys.description)
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
    let actions: SettingsActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AdapterGenerationPanel(
                message: generationMessage,
                preview: generatedPreview,
                canonicalByID: canonicalByID,
                actions: actions
            )

            TextField("Search apps", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(adapters) { adapter in
                SettingsAdapterRow(adapter: adapter, canonicalByID: canonicalByID)
            }

            if !validationMessages.isEmpty {
                Label(
                    "\(validationMessages.count) adapter files were skipped. Open the menu bar diagnostics for details.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundColor(ShortyBrand.amber)
            }
        }
        .padding()
    }
}

private struct AdapterGenerationPanel: View {
    let message: String?
    let preview: Adapter?
    let canonicalByID: [String: CanonicalShortcut]
    let actions: SettingsActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Generate Adapter")
                            .font(.headline)
                        Text("Create a local adapter from the active app's menus, then review it before saving.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Generate for Active App", action: actions.generateForActiveApp)
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
                    if adapter.source != .builtin {
                        Label("Review", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
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
            return "Send \(nativeKeys.description)"
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
