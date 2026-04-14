import ShortyCore
import SwiftUI

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
    case shortcuts
    case adapters
    case about
}

struct SettingsSnapshot {
    let shortcuts: [CanonicalShortcut]
    let adapters: [Adapter]
    let validationMessages: [String]
    let adapterGenerationMessage: String?
    let generatedAdapterPreview: Adapter?
    let versionBuild: String
    let engineStatus: String
    let accessibilityStatus: String
    let browserBridgeStatus: String

    static func live(engine: ShortcutEngine) -> SettingsSnapshot {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"

        return SettingsSnapshot(
            shortcuts: CanonicalShortcut.defaults,
            adapters: engine.registry.allAdapters,
            validationMessages: engine.registry.validationMessages,
            adapterGenerationMessage: engine.adapterGenerationMessage,
            generatedAdapterPreview: engine.generatedAdapterPreview,
            versionBuild: "\(version) (\(build))",
            engineStatus: engine.status.title,
            accessibilityStatus: ShortcutEngine.hasAccessibilityPermission ? "Granted" : "Not granted",
            browserBridgeStatus: engine.browserBridge?.status.title ?? "Unavailable"
        )
    }
}

struct SettingsActions {
    let generateForActiveApp: () -> Void
    let saveGeneratedAdapter: () -> Void
    let discardGeneratedAdapter: () -> Void

    static let noop = SettingsActions(
        generateForActiveApp: {},
        saveGeneratedAdapter: {},
        discardGeneratedAdapter: {}
    )

    static func live(engine: ShortcutEngine) -> SettingsActions {
        SettingsActions(
            generateForActiveApp: { engine.generateAdapterForCurrentApp() },
            saveGeneratedAdapter: { engine.saveGeneratedAdapterPreview() },
            discardGeneratedAdapter: { engine.discardGeneratedAdapterPreview() }
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
        initialTab: SettingsTab = .shortcuts,
        initialCategory: CanonicalShortcut.Category? = .navigation
    ) {
        self.snapshot = snapshot
        self.actions = actions
        _selectedTab = State(initialValue: initialTab)
        _selectedCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SettingsShortcutsTab(
                selectedCategory: $selectedCategory,
                searchText: $shortcutSearch,
                shortcuts: filteredShortcuts
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

            SettingsAboutTab(
                versionBuild: snapshot.versionBuild,
                engineStatus: snapshot.engineStatus,
                adapterCount: snapshot.adapters.count,
                shortcutCount: snapshot.shortcuts.count,
                accessibilityStatus: snapshot.accessibilityStatus,
                browserBridgeStatus: snapshot.browserBridgeStatus
            )
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
            .tag(SettingsTab.about)
        }
        .frame(width: 680, height: 480)
    }
}

private struct SettingsShortcutsTab: View {
    @Binding var selectedCategory: CanonicalShortcut.Category?
    @Binding var searchText: String

    let shortcuts: [CanonicalShortcut]

    var body: some View {
        HSplitView {
            SettingsCategoryList(selectedCategory: $selectedCategory)
            SettingsShortcutList(searchText: $searchText, shortcuts: shortcuts)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search shortcuts", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(shortcuts) { shortcut in
                SettingsShortcutRow(shortcut: shortcut)
            }
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
            Text(shortcut.defaultKeys.description)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
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
                .foregroundColor(.orange)
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
                            Text("\(canonicalName(mapping.canonicalID)): \(mappingDetail(mapping))")
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
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private func canonicalName(_ canonicalID: String) -> String {
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
                        Label("Review", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Shorty")
                .font(.title)
                .fontWeight(.bold)

            Text("One set of keyboard shortcuts for every app.")
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SettingsInfoRow("Version", versionBuild)
                SettingsInfoRow("Engine", engineStatus)
                SettingsInfoRow("Adapters loaded", "\(adapterCount)")
                SettingsInfoRow("Canonical shortcuts", "\(shortcutCount)")
                SettingsInfoRow("Accessibility", accessibilityStatus)
                SettingsInfoRow("Browser bridge", browserBridgeStatus)
            }

            Spacer()
        }
        .padding()
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
