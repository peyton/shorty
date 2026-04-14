import ShortyCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: ShortcutEngine
    @State private var selectedCategory: CanonicalShortcut.Category? = .navigation
    @State private var shortcutSearch = ""
    @State private var adapterSearch = ""

    private var canonicalByID: [String: CanonicalShortcut] {
        Dictionary(uniqueKeysWithValues: CanonicalShortcut.defaults.map { ($0.id, $0) })
    }

    var body: some View {
        TabView {
            shortcutsTab
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }

            adaptersTab
                .tabItem {
                    Label("Apps", systemImage: "app.dashed")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 720, height: 500)
    }

    private var shortcutsTab: some View {
        HSplitView {
            List(
                CanonicalShortcut.Category.allCases,
                id: \.self,
                selection: $selectedCategory
            ) { category in
                Label(category.rawValue.capitalized, systemImage: iconFor(category))
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150, maxWidth: 190)

            VStack(alignment: .leading, spacing: 10) {
                TextField("Search shortcuts", text: $shortcutSearch)
                    .textFieldStyle(.roundedBorder)

                List(filteredShortcuts) { shortcut in
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
            .padding()
        }
    }

    private var adaptersTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            adapterGenerationPanel

            TextField("Search apps", text: $adapterSearch)
                .textFieldStyle(.roundedBorder)

            List(filteredAdapters) { adapter in
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

            if !engine.registry.validationMessages.isEmpty {
                Label(
                    "\(engine.registry.validationMessages.count) adapter files were skipped. Open the menu bar diagnostics for details.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundColor(ShortyBrand.amber)
            }
        }
        .padding()
    }

    private var adapterGenerationPanel: some View {
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
                    Button("Generate for Active App") {
                        engine.generateAdapterForCurrentApp()
                    }
                }

                if let message = engine.adapterGenerationMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let preview = engine.generatedAdapterPreview {
                    DisclosureGroup("Generated preview for \(preview.appName)") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.mappings) { mapping in
                                Text("\(canonicalName(for: mapping.canonicalID)): \(mappingDetail(mapping))")
                                    .font(.caption)
                            }

                            HStack {
                                Button("Save Adapter") {
                                    engine.saveGeneratedAdapterPreview()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Discard") {
                                    engine.discardGeneratedAdapterPreview()
                                }
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

    private var aboutTab: some View {
        VStack(spacing: 16) {
            ShortyMarkView(size: 64)

            Text("Shorty")
                .font(.title)
                .fontWeight(.bold)

            Text("A local command map for macOS shortcuts.")
                .foregroundColor(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                infoRow("Version", versionBuild)
                infoRow("Engine", engine.status.title)
                infoRow("Adapters loaded", "\(engine.registry.allAdapters.count)")
                infoRow("Canonical shortcuts", "\(CanonicalShortcut.defaults.count)")
                infoRow(
                    "Accessibility",
                    ShortcutEngine.hasAccessibilityPermission ? "Granted" : "Not granted"
                )
                infoRow("Browser bridge", engine.browserBridge?.status.title ?? "Unavailable")
            }

            Spacer()
        }
        .padding()
    }

    private var filteredShortcuts: [CanonicalShortcut] {
        let query = shortcutSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return CanonicalShortcut.defaults.filter { shortcut in
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
        return engine.registry.allAdapters
            .filter { adapter in
                query.isEmpty
                    || adapter.appName.localizedCaseInsensitiveContains(query)
                    || adapter.appIdentifier.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.appName < $1.appName }
    }

    private var versionBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
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

    private func canonicalName(for canonicalID: String) -> String {
        canonicalByID[canonicalID]?.name ?? canonicalID
    }

    private func iconFor(_ category: CanonicalShortcut.Category) -> String {
        switch category {
        case .navigation: return "arrow.left.arrow.right"
        case .editing: return "pencil"
        case .tabs: return "square.on.square"
        case .windows: return "macwindow"
        case .search: return "magnifyingglass"
        case .media: return "play.circle"
        case .system: return "gear"
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
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
