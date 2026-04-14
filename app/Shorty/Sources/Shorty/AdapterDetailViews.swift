import AppKit
import ShortyCore
import SwiftUI

// MARK: - Adapter detail panel with app icon (#17)

/// Enhanced adapter row showing the app icon, source badge, and mapping count.
struct AdapterDetailRow: View {
    let adapter: Adapter
    let isEnabled: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            AdapterAppIcon(bundleIdentifier: adapter.appIdentifier)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(adapter.appName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(ShortyBrand.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ShortyBrand.teal.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    AdapterSourceBadge(source: adapter.source)
                    Text("\(adapter.mappings.count) mappings")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !isEnabled {
                Text("Paused")
                    .font(.caption2)
                    .foregroundColor(ShortyBrand.amber)
            }
        }
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(adapter.appName), \(adapter.source.rawValue), \(adapter.mappings.count) mappings\(isActive ? ", active" : "")\(isEnabled ? "" : ", paused")")
    }
}

/// Fetches the app icon from the bundle identifier.
struct AdapterAppIcon: View {
    let bundleIdentifier: String

    var body: some View {
        if bundleIdentifier.hasPrefix("web:") {
            Image(systemName: "globe")
                .foregroundColor(ShortyBrand.teal)
        } else if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path.path))
                .resizable()
        } else {
            Image(systemName: "app.fill")
                .foregroundColor(.secondary)
        }
    }
}

/// Badge showing the adapter's source (Built-in, Generated, User).
struct AdapterSourceBadge: View {
    let source: Adapter.Source

    var body: some View {
        Text(source.displayLabel)
            .font(.caption2.weight(.semibold))
            .foregroundColor(badgeColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.1), in: Capsule())
    }

    private var badgeColor: Color {
        switch source {
        case .builtin:
            return ShortyBrand.teal
        case .menuIntrospection, .llmGenerated:
            return .orange
        case .community:
            return .purple
        case .user:
            return .blue
        }
    }
}

private extension Adapter.Source {
    var displayLabel: String {
        switch self {
        case .builtin: return "Built-in"
        case .menuIntrospection: return "Generated"
        case .llmGenerated: return "AI Generated"
        case .community: return "Community"
        case .user: return "User"
        }
    }
}

// MARK: - Adapter diff view (#18)

/// Shows a diff between two adapters (e.g., generated vs. built-in).
struct AdapterDiffView: View {
    let generated: Adapter
    let builtIn: Adapter?

    private var addedMappings: [Adapter.Mapping] {
        guard let builtIn else { return generated.mappings }
        let builtInIDs = Set(builtIn.mappings.map(\.canonicalID))
        return generated.mappings.filter { !builtInIDs.contains($0.canonicalID) }
    }

    private var removedMappings: [Adapter.Mapping] {
        guard let builtIn else { return [] }
        let generatedIDs = Set(generated.mappings.map(\.canonicalID))
        return builtIn.mappings.filter { !generatedIDs.contains($0.canonicalID) }
    }

    private var changedMappings: [(generated: Adapter.Mapping, builtIn: Adapter.Mapping)] {
        guard let builtIn else { return [] }
        let builtInByID = Dictionary(uniqueKeysWithValues: builtIn.mappings.map { ($0.canonicalID, $0) })
        return generated.mappings.compactMap { mapping in
            guard let existing = builtInByID[mapping.canonicalID],
                  mapping != existing
            else { return nil }
            return (generated: mapping, builtIn: existing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if builtIn != nil {
                Text("Changes from built-in adapter")
                    .font(.caption.weight(.semibold))
            }

            if !addedMappings.isEmpty {
                DiffSection(title: "Added", color: ShortyBrand.teal, mappings: addedMappings)
            }
            if !changedMappings.isEmpty {
                Text("Changed (\(changedMappings.count))")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(ShortyBrand.amber)
                ForEach(changedMappings, id: \.generated.canonicalID) { pair in
                    HStack(spacing: 4) {
                        Text(pair.generated.canonicalID)
                            .font(.caption2)
                        Text("→")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(pair.generated.method.rawValue)
                            .font(.caption2.weight(.medium))
                    }
                }
            }
            if !removedMappings.isEmpty {
                DiffSection(title: "Removed", color: .red, mappings: removedMappings)
            }
        }
    }
}

private struct DiffSection: View {
    let title: String
    let color: Color
    let mappings: [Adapter.Mapping]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) (\(mappings.count))")
                .font(.caption2.weight(.semibold))
                .foregroundColor(color)
            ForEach(mappings, id: \.canonicalID) { mapping in
                Text(mapping.canonicalID)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Adapter quality score (#30)

/// Shows a confidence score for generated adapters.
struct AdapterQualityBadge: View {
    let adapter: Adapter

    private var menuVerifiedCount: Int {
        adapter.mappings.filter { $0.method == .menuInvoke && $0.menuTitle != nil }.count
    }

    private var keyRemapCount: Int {
        adapter.mappings.filter { $0.method == .keyRemap }.count
    }

    private var passthroughCount: Int {
        adapter.mappings.filter { $0.method == .passthrough }.count
    }

    private var qualityPercentage: Int {
        guard !adapter.mappings.isEmpty else { return 0 }
        let verified = menuVerifiedCount + passthroughCount
        return (verified * 100) / adapter.mappings.count
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(qualityColor)
                .frame(width: 8, height: 8)
            Text("\(qualityPercentage)% verified")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("(\(menuVerifiedCount) menu, \(keyRemapCount) remap, \(passthroughCount) native)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityLabel("\(qualityPercentage) percent of mappings verified")
    }

    private var qualityColor: Color {
        if qualityPercentage >= 80 { return ShortyBrand.teal }
        if qualityPercentage >= 50 { return ShortyBrand.amber }
        return .red
    }
}
