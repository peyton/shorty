import SwiftUI
import ShortyCore

/// The Settings window — shows canonical shortcuts and per-app adapters.
struct SettingsView: View {
    @ObservedObject var engine: ShortcutEngine
    @State private var selectedCategory: CanonicalShortcut.Category? = .navigation

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
        .frame(width: 600, height: 420)
    }

    // MARK: - Shortcuts tab

    private var shortcutsTab: some View {
        HSplitView {
            // Category sidebar
            List(CanonicalShortcut.Category.allCases, id: \.self,
                 selection: $selectedCategory) { category in
                Label(category.rawValue.capitalized,
                      systemImage: iconFor(category))
            }
            .listStyle(.sidebar)
            .frame(minWidth: 140, maxWidth: 180)

            // Shortcut list
            List {
                let shortcuts = CanonicalShortcut.defaults.filter {
                    selectedCategory == nil || $0.category == selectedCategory
                }
                ForEach(shortcuts) { shortcut in
                    HStack {
                        VStack(alignment: .leading) {
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
        }
    }

    // MARK: - Adapters tab

    private var adaptersTab: some View {
        List {
            let adapters = engine.registry.allAdapters
                .sorted { $0.appName < $1.appName }
            ForEach(adapters) { adapter in
                DisclosureGroup {
                    ForEach(adapter.mappings) { mapping in
                        HStack {
                            Text(mapping.canonicalID)
                                .font(.caption.monospaced())
                            Spacer()
                            Text(mapping.method.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let nk = mapping.nativeKeys {
                                Text(nk.description)
                                    .font(.caption.monospaced())
                            }
                            if let menu = mapping.menuTitle {
                                Text(""\(menu)"")
                                    .font(.caption)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(adapter.appName)
                            .fontWeight(.medium)
                        Text("(\(adapter.source.rawValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(adapter.mappings.count) mappings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - About tab

    private var aboutTab: some View {
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
                infoRow("Event tap", engine.isRunning ? "Active ✓" : "Inactive ✗")
                infoRow("Adapters loaded", "\(engine.registry.allAdapters.count)")
                infoRow("Canonical shortcuts", "\(CanonicalShortcut.defaults.count)")
                infoRow("Accessibility",
                        ShortcutEngine.hasAccessibilityPermission
                            ? "Granted ✓" : "Not granted ✗")
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers

    private func iconFor(_ category: CanonicalShortcut.Category) -> String {
        switch category {
        case .navigation: return "arrow.left.arrow.right"
        case .editing:    return "pencil"
        case .tabs:       return "square.on.square"
        case .windows:    return "macwindow"
        case .search:     return "magnifyingglass"
        case .media:      return "play.circle"
        case .system:     return "gear"
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
