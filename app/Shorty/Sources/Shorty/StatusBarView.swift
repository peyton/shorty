import AppKit
import ShortyCore
import SwiftUI

struct StatusBarView: View {
    @ObservedObject var engine: ShortcutEngine

    var body: some View {
        StatusBarContentView(
            snapshot: .live(engine: engine),
            eventTapEnabled: eventTapEnabledBinding,
            actions: .live(engine: engine)
        )
    }

    private var eventTapEnabledBinding: Binding<Bool> {
        Binding(
            get: { engine.eventTap.isEnabled },
            set: { engine.eventTap.isEnabled = $0 }
        )
    }
}

struct StatusBarSnapshot {
    let statusTitle: String
    let statusDetail: String
    let statusIsHealthy: Bool
    let currentAppName: String
    let coverageText: String
    let lifecycleMessage: String?
    let requiresPermission: Bool
    let effectiveID: String
    let adapterSource: String
    let mappingCount: String
    let webDomain: String
    let bridgeStatus: String
    let eventsIntercepted: Int
    let eventsRemapped: Int
    let validationMessages: [String]

    static func live(engine: ShortcutEngine) -> StatusBarSnapshot {
        let appID = engine.appMonitor.effectiveAppID
        let adapter = appID.flatMap { engine.registry.activeAdapter(for: $0) }

        let coverageText: String
        if !engine.eventTap.isEnabled {
            coverageText = "Paused"
        } else if let adapter {
            coverageText = "\(adapter.mappings.count) shortcuts for \(adapter.appName)"
        } else {
            coverageText = "Pass through"
        }

        let normalizedWebDomain: String
        if let domain = engine.appMonitor.webAppDomain {
            normalizedWebDomain = DomainNormalizer.normalizedDomain(for: domain)
        } else {
            normalizedWebDomain = "None"
        }

        return StatusBarSnapshot(
            statusTitle: engine.status.title,
            statusDetail: engine.status.detail,
            statusIsHealthy: engine.status.isHealthy,
            currentAppName: engine.appMonitor.currentAppName ?? "Unknown",
            coverageText: coverageText,
            lifecycleMessage: engine.eventTap.lifecycleMessage,
            requiresPermission: engine.status == .permissionRequired,
            effectiveID: appID ?? "None",
            adapterSource: adapter?.source.rawValue ?? "none",
            mappingCount: adapter.map { "\($0.mappings.count)" } ?? "0",
            webDomain: normalizedWebDomain,
            bridgeStatus: engine.browserBridge?.status.title ?? "Unavailable",
            eventsIntercepted: engine.eventTap.eventsIntercepted,
            eventsRemapped: engine.eventTap.eventsRemapped,
            validationMessages: engine.registry.validationMessages
        )
    }
}

struct StatusBarActions {
    let openAccessibilitySettings: () -> Void
    let checkAgain: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    static let noop = StatusBarActions(
        openAccessibilitySettings: {},
        checkAgain: {},
        openSettings: {},
        quit: {}
    )

    static func live(engine: ShortcutEngine) -> StatusBarActions {
        StatusBarActions(
            openAccessibilitySettings: { ShortcutEngine.requestAccessibilityPermission() },
            checkAgain: { engine.checkAccessibilityAndRetry() },
            openSettings: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            quit: {
                engine.stop()
                NSApp.terminate(nil)
            }
        )
    }
}

struct StatusBarContentView: View {
    let snapshot: StatusBarSnapshot
    let eventTapEnabled: Binding<Bool>
    let actions: StatusBarActions

    @State private var showsPermissionHelp: Bool
    @State private var showsAdvancedDiagnostics: Bool

    init(
        snapshot: StatusBarSnapshot,
        eventTapEnabled: Binding<Bool>,
        actions: StatusBarActions = .noop,
        showsPermissionHelp: Bool = false,
        showsAdvancedDiagnostics: Bool = false
    ) {
        self.snapshot = snapshot
        self.eventTapEnabled = eventTapEnabled
        self.actions = actions
        _showsPermissionHelp = State(initialValue: showsPermissionHelp)
        _showsAdvancedDiagnostics = State(initialValue: showsAdvancedDiagnostics)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusBarHeader(snapshot: snapshot)
            Divider()
            StatusSummarySection(snapshot: snapshot)
            ActiveAppSection(snapshot: snapshot)
            PermissionSection(
                snapshot: snapshot,
                showsPermissionHelp: $showsPermissionHelp,
                actions: actions
            )
            Divider()
            StatusControlsSection(
                snapshot: snapshot,
                eventTapEnabled: eventTapEnabled
            )
            AdvancedDiagnosticsSection(
                snapshot: snapshot,
                showsAdvancedDiagnostics: $showsAdvancedDiagnostics
            )
            StatusFooter(actions: actions)
        }
        .padding()
        .frame(width: 340)
    }
}

private struct StatusBarHeader: View {
    let snapshot: StatusBarSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shorty")
                    .font(.headline)
                Text("Shortcut translation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Circle()
                .fill(snapshot.statusIsHealthy ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
                .accessibilityLabel(snapshot.statusTitle)
        }
    }
}

private struct StatusSummarySection: View {
    let snapshot: StatusBarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.statusTitle)
                .font(.callout)
                .fontWeight(.semibold)
            Text(snapshot.statusDetail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ActiveAppSection: View {
    let snapshot: StatusBarSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusInfoRow("Active app", snapshot.currentAppName)
            StatusInfoRow("Coverage", snapshot.coverageText)
            if let lifecycleMessage = snapshot.lifecycleMessage {
                Label(lifecycleMessage, systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct PermissionSection: View {
    let snapshot: StatusBarSnapshot
    @Binding var showsPermissionHelp: Bool
    let actions: StatusBarActions

    var body: some View {
        if snapshot.requiresPermission {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Open Accessibility Settings", action: actions.openAccessibilitySettings)
                        .buttonStyle(.borderedProminent)

                    Button("Check Again", action: actions.checkAgain)
                }
                .controlSize(.small)

                DisclosureGroup("What Shorty needs", isExpanded: $showsPermissionHelp) {
                    Text("Shorty uses macOS Accessibility permission to listen for your shortcut keys and translate them only for supported apps. It does not need a network service for native app shortcuts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .font(.caption)
            }
        }
    }
}

private struct StatusControlsSection: View {
    let snapshot: StatusBarSnapshot
    let eventTapEnabled: Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Shorty enabled", isOn: eventTapEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(snapshot.requiresPermission)

            if !eventTapEnabled.wrappedValue {
                Text("Shorty is passing every shortcut through unchanged.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct AdvancedDiagnosticsSection: View {
    let snapshot: StatusBarSnapshot
    @Binding var showsAdvancedDiagnostics: Bool

    var body: some View {
        DisclosureGroup("Advanced Diagnostics", isExpanded: $showsAdvancedDiagnostics) {
            VStack(alignment: .leading, spacing: 8) {
                StatusInfoRow("Effective ID", snapshot.effectiveID)
                StatusInfoRow("Adapter source", snapshot.adapterSource)
                StatusInfoRow("Mappings", snapshot.mappingCount)
                StatusInfoRow("Web domain", snapshot.webDomain)
                StatusInfoRow("Bridge", snapshot.bridgeStatus)
                StatusInfoRow("Intercepted", "\(snapshot.eventsIntercepted)")
                StatusInfoRow("Remapped", "\(snapshot.eventsRemapped)")

                if !snapshot.validationMessages.isEmpty {
                    Text("Adapter validation warnings")
                        .font(.caption)
                        .fontWeight(.semibold)
                    ForEach(snapshot.validationMessages, id: \.self) { message in
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.top, 6)
        }
        .font(.caption)
    }
}

private struct StatusFooter: View {
    let actions: StatusBarActions

    var body: some View {
        HStack {
            Button("Settings...", action: actions.openSettings)

            Spacer()

            Button("Quit", action: actions.quit)
        }
    }
}

private struct StatusInfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }
}
