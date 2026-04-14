import ShortyCore
import SwiftUI

/// A searchable item that can appear across any settings tab (#13).
struct SettingsSearchResult: Identifiable {
    let id: String
    let title: String
    let detail: String
    let tab: SettingsTab
    let category: String

    enum Kind {
        case shortcut(CanonicalShortcut)
        case adapter(Adapter)
        case setting(String)
    }

    let kind: Kind
}

/// Builds search results from settings state.
enum SettingsSearchIndex {
    static func search(
        query: String,
        shortcuts: [CanonicalShortcut],
        adapters: [Adapter]
    ) -> [SettingsSearchResult] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        var results: [SettingsSearchResult] = []

        for shortcut in shortcuts {
            if shortcut.name.lowercased().contains(q)
                || shortcut.description.lowercased().contains(q)
                || shortcut.id.lowercased().contains(q)
                || shortcut.defaultKeys.displayString.lowercased().contains(q) {
                results.append(SettingsSearchResult(
                    id: "shortcut-\(shortcut.id)",
                    title: shortcut.name,
                    detail: "\(shortcut.defaultKeys.displayString) — \(shortcut.description)",
                    tab: .shortcuts,
                    category: "Shortcuts",
                    kind: .shortcut(shortcut)
                ))
            }
        }

        for adapter in adapters {
            if adapter.appName.lowercased().contains(q)
                || adapter.appIdentifier.lowercased().contains(q) {
                results.append(SettingsSearchResult(
                    id: "adapter-\(adapter.appIdentifier)",
                    title: adapter.appName,
                    detail: "\(adapter.mappings.count) mappings — \(adapter.source.rawValue)",
                    tab: .adapters,
                    category: "Apps",
                    kind: .adapter(adapter)
                ))
            }

            for mapping in adapter.mappings {
                if mapping.canonicalID.lowercased().contains(q)
                    || (mapping.menuTitle?.lowercased().contains(q) ?? false)
                    || (mapping.nativeKeys?.displayString.lowercased().contains(q) ?? false) {
                    results.append(SettingsSearchResult(
                        id: "mapping-\(adapter.appIdentifier)-\(mapping.canonicalID)",
                        title: "\(mapping.canonicalID) in \(adapter.appName)",
                        detail: mapping.menuTitle ?? mapping.nativeKeys?.displayString ?? mapping.method.rawValue,
                        tab: .adapters,
                        category: "Mappings",
                        kind: .adapter(adapter)
                    ))
                }
            }
        }

        let settingNames: [(String, String, SettingsTab)] = [
            ("Accessibility", "System permission for keyboard interception", .setup),
            ("Launch at Login", "Start Shorty when macOS boots", .setup),
            ("Browser Bridge", "Chrome extension for web app shortcuts", .advanced),
            ("Safari Extension", "Safari support for web app shortcuts", .advanced),
            ("Automatic Updates", "Check for new versions", .advanced),
            ("Export Support Bundle", "Diagnostics for troubleshooting", .advanced),
            ("App Coverage", "Scan installed apps for adapter coverage", .adapters),
            ("Translation Sound", "Audio feedback for shortcut translation", .advanced),
            ("Weekly Digest", "Weekly summary notification", .advanced),
        ]

        for (name, detail, tab) in settingNames {
            if name.lowercased().contains(q) || detail.lowercased().contains(q) {
                results.append(SettingsSearchResult(
                    id: "setting-\(name)",
                    title: name,
                    detail: detail,
                    tab: tab,
                    category: "Settings",
                    kind: .setting(name)
                ))
            }
        }

        return results
    }
}

/// The global search bar shown at the top of the Settings window (#13).
struct GlobalSettingsSearchBar: View {
    @Binding var searchText: String
    @Binding var selectedTab: SettingsTab
    let results: [SettingsSearchResult]

    @State private var showResults = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search all settings... (⌘F)", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit {
                        if let first = results.first {
                            selectedTab = first.tab
                            searchText = ""
                        }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.06))

            if !results.isEmpty {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(results) { result in
                            Button {
                                selectedTab = result.tab
                                searchText = ""
                            } label: {
                                SearchResultRow(result: result)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 200)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search all settings")
    }
}

private struct SearchResultRow: View {
    let result: SettingsSearchResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForTab(result.tab))
                .foregroundColor(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.caption.weight(.medium))
                Text(result.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(result.category)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.08), in: Capsule())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title) in \(result.category)")
    }

    private func iconForTab(_ tab: SettingsTab) -> String {
        switch tab {
        case .setup: return "checklist"
        case .shortcuts: return "command"
        case .adapters: return "app.dashed"
        case .advanced: return "slider.horizontal.3"
        }
    }
}
