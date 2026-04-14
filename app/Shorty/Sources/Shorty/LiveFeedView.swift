import ShortyCore
import SwiftUI

/// Shows the last N translated shortcuts in real time (#6).
/// Replaces or supplements the static shortcut list in the popover.
struct LiveFeedView: View {
    let events: [TranslationEvent]
    let canonicalShortcuts: [CanonicalShortcut]

    var body: some View {
        if events.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(events.suffix(8).reversed()) { event in
                        LiveFeedRow(event: event)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 200)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .foregroundColor(.secondary)
            Text("Shortcut activity will appear here as you use your apps.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct LiveFeedRow: View {
    let event: TranslationEvent

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            ShortcutKeyBadge(text: event.inputKeys.displayString)
                .frame(minWidth: 50, alignment: .trailing)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.canonicalName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(event.actionDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(relativeTime)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.canonicalName), \(event.inputKeys.displayString), \(event.actionDescription)")
    }

    private var statusColor: Color {
        if event.succeeded == false {
            return ShortyBrand.amber
        }
        return ShortyBrand.teal
    }

    private var relativeTime: String {
        let interval = Date().timeIntervalSince(event.timestamp)
        if interval < 5 {
            return "now"
        } else if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        }
        return "\(Int(interval / 3600))h"
    }
}
