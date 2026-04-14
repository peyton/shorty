import ShortyCore
import SwiftUI

/// Quick search field for filtering shortcuts in the popover (#8).
struct PopoverSearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.caption)
            TextField("Search shortcuts...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.caption)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search shortcuts")
    }
}

/// Shortcuts grouped by category with collapsible headers (#9).
struct CategoryGroupedShortcutList: View {
    let shortcuts: [ShortcutRowPresentation]

    private var groupedShortcuts: [(category: String, shortcuts: [ShortcutRowPresentation])] {
        let grouped = Dictionary(grouping: shortcuts) { shortcut in
            categoryForCanonicalID(shortcut.id)
        }
        return grouped
            .sorted { categoryOrder($0.key) < categoryOrder($1.key) }
            .map { (category: $0.key, shortcuts: $0.value) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(groupedShortcuts, id: \.category) { group in
                    CategoryHeader(title: group.category)
                    ForEach(group.shortcuts) { shortcut in
                        GroupedShortcutRow(shortcut: shortcut)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxHeight: 260)
    }

    private func categoryForCanonicalID(_ id: String) -> String {
        let categories: [String: String] = [
            "focus_url_bar": "Navigation", "go_back": "Navigation", "go_forward": "Navigation",
            "newline_in_field": "Editing", "submit_field": "Editing", "select_all": "Editing",
            "find_in_page": "Search", "find_and_replace": "Search", "command_palette": "Search",
            "spotlight_search": "Search",
            "new_tab": "Tabs", "close_tab": "Tabs", "next_tab": "Tabs",
            "prev_tab": "Tabs", "reopen_tab": "Tabs",
            "new_window": "Windows", "close_window": "Windows", "minimize_window": "Windows",
            "toggle_play_pause": "Media"
        ]
        return categories[id] ?? "Other"
    }

    private func categoryOrder(_ name: String) -> Int {
        let order = ["Navigation": 0, "Search": 1, "Editing": 2, "Tabs": 3, "Windows": 4, "Media": 5, "Other": 6]
        return order[name] ?? 99
    }
}

private struct CategoryHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct GroupedShortcutRow: View {
    let shortcut: ShortcutRowPresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ShortcutKeyBadge(text: shortcut.defaultKeys)
                .frame(minWidth: 58, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(shortcut.actionDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            ShortcutActionPillPublic(kind: shortcut.actionKind)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(shortcut.name), \(shortcut.defaultKeys), \(shortcut.actionDescription)"
        )
    }
}

/// Public version of ShortcutActionPill for use across files.
struct ShortcutActionPillPublic: View {
    let kind: AvailableShortcutActionKind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

/// Empty state with contextual action for apps without adapters (#7).
struct ContextualEmptyState: View {
    let appName: String
    let appIcon: NSImage?
    let hasPermission: Bool
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 40, height: 40)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 4) {
                Text("No shortcuts for \(appName)")
                    .font(.callout.weight(.medium))
                Text("Shorty will pass keys through until you add support.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if hasPermission {
                Button("Generate Shortcuts for \(appName)") {
                    onGenerate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No shortcuts for \(appName)")
    }
}
