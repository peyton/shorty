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
    let status: EngineDisplayStatus
    let currentAppName: String
    let activeContextTitle: String
    let availability: ShortcutAvailability
    let lifecycleMessage: String?
    let effectiveID: String
    let adapterSource: String
    let mappingCount: String
    let webDomain: String
    let browserContextSource: String
    let bridgeStatus: String
    let safariExtensionStatus: String
    let shortcutReviewCount: Int
    let eventsIntercepted: Int
    let eventsMatched: Int
    let eventsRemapped: Int
    let eventsPassedThrough: Int
    let menuActionsInvoked: Int
    let accessibilityActionsInvoked: Int
    let validationMessages: [String]
    let adapterGenerationMessage: String?
    let hasGeneratedAdapterPreview: Bool

    var requiresPermission: Bool {
        status.requiresPermission
    }

    var statusTitle: String {
        status.title
    }

    var statusDetail: String {
        status.detail
    }

    var statusIsHealthy: Bool {
        status.isHealthy
    }

    static func live(engine: ShortcutEngine) -> StatusBarSnapshot {
        let appID = engine.appMonitor.effectiveAppID
        let activeTitle = activeContextTitle(engine: engine, appID: appID)
        let availability = engine.registry.availability(
            for: appID,
            displayName: activeTitle
        )

        let normalizedWebDomain: String
        if let domain = engine.appMonitor.webAppDomain {
            normalizedWebDomain = DomainNormalizer.normalizedDomain(for: domain)
        } else {
            normalizedWebDomain = "None"
        }

        return StatusBarSnapshot(
            status: EngineDisplayStatus.make(
                status: engine.status,
                permissionState: engine.permissionState,
                eventTapEnabled: engine.eventTap.isEnabled,
                isWaitingForPermission: engine.isWaitingForAccessibilityPermission
            ),
            currentAppName: engine.appMonitor.currentAppName ?? "Unknown",
            activeContextTitle: activeTitle,
            availability: availability,
            lifecycleMessage: importantLifecycleMessage(engine: engine),
            effectiveID: appID ?? "None",
            adapterSource: availability.adapterSource?.statusLabel ?? "none",
            mappingCount: "\(availability.shortcuts.count)",
            webDomain: normalizedWebDomain,
            browserContextSource: engine.appMonitor.browserContextSource.title,
            bridgeStatus: engine.browserBridge?.status.title ?? "Unavailable",
            safariExtensionStatus: engine.safariExtensionStatus.title,
            shortcutReviewCount: engine.shortcutProfile.conflicts().count,
            eventsIntercepted: engine.eventTap.eventsIntercepted,
            eventsMatched: engine.eventTap.shortcutsMatched,
            eventsRemapped: engine.eventTap.eventsRemapped,
            eventsPassedThrough: engine.eventTap.counters.eventsPassedThrough,
            menuActionsInvoked: engine.eventTap.counters.menuActionsInvoked,
            accessibilityActionsInvoked: engine.eventTap.counters.accessibilityActionsInvoked,
            validationMessages: engine.registry.validationMessages,
            adapterGenerationMessage: engine.adapterGenerationMessage,
            hasGeneratedAdapterPreview: engine.generatedAdapterPreview != nil
        )
    }

    private static func activeContextTitle(
        engine: ShortcutEngine,
        appID: String?
    ) -> String {
        let appName = engine.appMonitor.currentAppName ?? "Unknown"
        guard let domain = engine.appMonitor.webAppDomain,
              let appID,
              appID.hasPrefix("web:")
        else {
            return appName
        }

        let adapterName = engine.registry.activeAdapter(for: appID)?.appName
            ?? DomainNormalizer.normalizedDomain(for: domain)
        return "\(adapterName) in \(appName)"
    }

    private static func importantLifecycleMessage(engine: ShortcutEngine) -> String? {
        guard engine.eventTap.isEnabled else { return nil }
        return engine.eventTap.lifecycleMessage
    }
}

struct StatusBarActions {
    let openAccessibilitySettings: () -> Void
    let addCurrentApp: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    static let noop = StatusBarActions(
        openAccessibilitySettings: {},
        addCurrentApp: {},
        openSettings: {},
        quit: {}
    )

    static func live(engine: ShortcutEngine) -> StatusBarActions {
        StatusBarActions(
            openAccessibilitySettings: { engine.openAccessibilitySettings() },
            addCurrentApp: { engine.generateAdapterForCurrentApp() },
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

    @State private var showsDetails: Bool

    init(
        snapshot: StatusBarSnapshot,
        eventTapEnabled: Binding<Bool>,
        actions: StatusBarActions = .noop,
        showsDetails: Bool = false
    ) {
        self.snapshot = snapshot
        self.eventTapEnabled = eventTapEnabled
        self.actions = actions
        _showsDetails = State(initialValue: showsDetails)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusHeader(snapshot: snapshot)
            PermissionBanner(snapshot: snapshot, actions: actions)
            AvailableShortcutsSection(snapshot: snapshot, actions: actions)
            TranslationControlSection(
                snapshot: snapshot,
                eventTapEnabled: eventTapEnabled
            )
            DetailsSection(snapshot: snapshot, showsDetails: $showsDetails)
            StatusFooter(actions: actions)
        }
        .padding(16)
        .frame(width: 430)
    }
}

private struct StatusHeader: View {
    let snapshot: StatusBarSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ShortyMenuBarGlyph(status: engineStatusForGlyph)
                .accessibilityLabel(snapshot.status.title)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(snapshot.status.title)
                        .font(.headline)
                    CoverageBadge(availability: snapshot.availability)
                }
                Text(snapshot.activeContextTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.status.title), \(snapshot.activeContextTitle)")
    }

    private var engineStatusForGlyph: EngineStatus {
        if snapshot.requiresPermission {
            return .permissionRequired
        }
        if snapshot.status.title == "Paused" {
            return .disabled
        }
        return snapshot.status.isHealthy ? .running : .failed(snapshot.status.detail)
    }
}

private struct CoverageBadge: View {
    let availability: ShortcutAvailability

    var body: some View {
        Text(availability.coverageTitle)
            .font(.caption.weight(.semibold))
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel("Coverage: \(availability.coverageTitle)")
    }

    private var foregroundColor: Color {
        switch availability.state {
        case .available:
            return ShortyBrand.teal
        case .noActiveApp, .noAdapter:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch availability.state {
        case .available:
            return ShortyBrand.teal.opacity(0.12)
        case .noActiveApp, .noAdapter:
            return Color.secondary.opacity(0.12)
        }
    }
}

private struct PermissionBanner: View {
    let snapshot: StatusBarSnapshot
    let actions: StatusBarActions

    var body: some View {
        if snapshot.requiresPermission {
            ShortyPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.status.title)
                                .font(.callout.weight(.semibold))
                            Text(snapshot.status.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "accessibility")
                            .foregroundColor(ShortyBrand.amber)
                    }

                    HStack(spacing: 10) {
                        Button(
                            "Open Accessibility Settings",
                            action: actions.openAccessibilitySettings
                        )
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if snapshot.status.isWaitingForPermission {
                            ProgressView()
                                .controlSize(.small)
                            Text("Watching for approval")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(snapshot.status.title)
        }
    }
}

private struct AvailableShortcutsSection: View {
    let snapshot: StatusBarSnapshot
    let actions: StatusBarActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Available now")
                            .font(.callout.weight(.semibold))
                        Text(snapshot.availability.coverageDetail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                switch snapshot.availability.state {
                case .available:
                    ShortcutList(shortcuts: snapshot.availability.shortcuts)
                case .noActiveApp:
                    EmptyShortcutState(
                        title: "No app selected",
                        detail: "Click into an app and Shorty will show its shortcuts here.",
                        showsAddButton: false,
                        actions: actions
                    )
                case .noAdapter:
                    EmptyShortcutState(
                        title: "No shortcuts for this app yet",
                        detail: "Shorty will pass keys through until you add support for this app.",
                        showsAddButton: !snapshot.requiresPermission,
                        actions: actions
                    )
                }

                if let message = snapshot.adapterGenerationMessage {
                    AdapterGenerationMessage(
                        message: message,
                        hasPreview: snapshot.hasGeneratedAdapterPreview
                    )
                }
            }
        }
    }
}

private struct ShortcutList: View {
    let shortcuts: [AvailableShortcut]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    AvailableShortcutRow(shortcut: shortcut)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxHeight: 260)
    }
}

private struct AvailableShortcutRow: View {
    let shortcut: AvailableShortcut

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ShortcutKeyBadge(text: shortcut.defaultKeys.displayString)
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

            ShortcutActionPill(kind: shortcut.actionKind)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(shortcut.name), \(shortcut.defaultKeys.displayString), \(shortcut.actionDescription)"
        )
    }
}

private struct ShortcutActionPill: View {
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

private struct EmptyShortcutState: View {
    let title: String
    let detail: String
    let showsAddButton: Bool
    let actions: StatusBarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "keyboard.badge.ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if showsAddButton {
                Button("Add Current App", action: actions.addCurrentApp)
                    .controlSize(.small)
            }
        }
    }
}

private struct AdapterGenerationMessage: View {
    let message: String
    let hasPreview: Bool

    var body: some View {
        Label(
            hasPreview ? "\(message) Open Apps settings to review it." : message,
            systemImage: hasPreview ? "checkmark.circle" : "info.circle"
        )
        .font(.caption)
        .foregroundColor(hasPreview ? ShortyBrand.teal : .secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TranslationControlSection: View {
    let snapshot: StatusBarSnapshot
    let eventTapEnabled: Binding<Bool>

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcut translation")
                    .font(.caption.weight(.semibold))
                Text(controlDetail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("Shortcut translation", isOn: eventTapEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(snapshot.requiresPermission)
                .accessibilityLabel("Shortcut translation")
        }
    }

    private var controlDetail: String {
        if snapshot.requiresPermission {
            return "Blocked until Accessibility access is granted."
        }
        if eventTapEnabled.wrappedValue {
            return "Ready for supported apps."
        }
        return "Paused by you."
    }
}

private struct DetailsSection: View {
    let snapshot: StatusBarSnapshot
    @Binding var showsDetails: Bool

    var body: some View {
        DisclosureGroup("Details", isExpanded: $showsDetails) {
            VStack(alignment: .leading, spacing: 8) {
                if let lifecycleMessage = snapshot.lifecycleMessage {
                    Label(lifecycleMessage, systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                StatusInfoRow("Effective app", snapshot.effectiveID)
                StatusInfoRow("Adapter", snapshot.adapterSource)
                StatusInfoRow("Mappings", snapshot.mappingCount)
                StatusInfoRow("Web domain", snapshot.webDomain)
                StatusInfoRow("Browser source", snapshot.browserContextSource)
                StatusInfoRow("Bridge", snapshot.bridgeStatus)
                StatusInfoRow("Safari", snapshot.safariExtensionStatus)
                StatusInfoRow("Shortcut review", "\(snapshot.shortcutReviewCount)")
                StatusInfoRow("Key events seen", "\(snapshot.eventsIntercepted)")
                StatusInfoRow("Shortcuts matched", "\(snapshot.eventsMatched)")
                StatusInfoRow("Key remaps", "\(snapshot.eventsRemapped)")
                StatusInfoRow("Native pass-throughs", "\(snapshot.eventsPassedThrough)")
                StatusInfoRow("Menu actions", "\(snapshot.menuActionsInvoked)")
                StatusInfoRow("Accessibility actions", "\(snapshot.accessibilityActionsInvoked)")

                if !snapshot.validationMessages.isEmpty {
                    Label(
                        "\(snapshot.validationMessages.count) adapter warning\(snapshot.validationMessages.count == 1 ? "" : "s")",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundColor(ShortyBrand.amber)
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
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }
}

private extension Adapter.Source {
    var statusLabel: String {
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
