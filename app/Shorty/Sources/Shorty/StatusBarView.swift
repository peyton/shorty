import AppKit
import ShortyCore
import SwiftUI

struct StatusBarView: View {
    @ObservedObject var engine: ShortcutEngine
    @State private var showsPermissionHelp = false
    @State private var showsAdvancedDiagnostics = false

    private var adapter: Adapter? {
        guard let appID = engine.appMonitor.effectiveAppID else {
            return nil
        }
        return engine.registry.activeAdapter(for: appID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusSummary
            activeAppSummary
            permissionActions
            Divider()
            controls
            advancedDiagnostics
            footer
        }
        .padding()
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ShortyMarkView(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shorty")
                    .font(.headline)
                Text("Command map")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ShortyStatusDot(status: engine.status)
        }
    }

    private var statusSummary: some View {
        ShortyPanel {
            HStack(alignment: .top, spacing: 10) {
                Image(
                    systemName: engine.status.isHealthy
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                    .foregroundColor(ShortyBrand.statusColor(for: engine.status))
                    .font(.callout)
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.status.title)
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text(engine.status.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var activeAppSummary: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                infoRow("Active app", engine.appMonitor.currentAppName ?? "Unknown")
                infoRow("Coverage", coverageText)
                if let lifecycleMessage = engine.eventTap.lifecycleMessage {
                    Label(lifecycleMessage, systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var permissionActions: some View {
        if engine.status == .permissionRequired {
            ShortyPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("Open Accessibility Settings") {
                            ShortcutEngine.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Check Again") {
                            engine.checkAccessibilityAndRetry()
                        }
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

    private var controls: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Shorty enabled", isOn: eventTapEnabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(engine.status == .permissionRequired)

                if !engine.eventTap.isEnabled {
                    Text("Shorty is passing every shortcut through unchanged.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var advancedDiagnostics: some View {
        ShortyPanel {
            DisclosureGroup("Advanced Diagnostics", isExpanded: $showsAdvancedDiagnostics) {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("Effective ID", engine.appMonitor.effectiveAppID ?? "None")
                    infoRow("Adapter source", adapter?.source.rawValue ?? "none")
                    infoRow("Mappings", adapter.map { "\($0.mappings.count)" } ?? "0")
                    infoRow("Web domain", normalizedWebDomain)
                    infoRow("Bridge", engine.browserBridge?.status.title ?? "Unavailable")
                    infoRow("Intercepted", "\(engine.eventTap.eventsIntercepted)")
                    infoRow("Remapped", "\(engine.eventTap.eventsRemapped)")

                    if !engine.registry.validationMessages.isEmpty {
                        Text("Adapter validation warnings")
                            .font(.caption)
                            .fontWeight(.semibold)
                        ForEach(engine.registry.validationMessages, id: \.self) { message in
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

    private var footer: some View {
        HStack {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }

            Spacer()

            Button("Quit") {
                engine.stop()
                NSApp.terminate(nil)
            }
        }
    }

    private var coverageText: String {
        if !engine.eventTap.isEnabled {
            return "Paused"
        }
        guard let adapter else {
            return "Pass through"
        }
        return "\(adapter.mappings.count) shortcuts for \(adapter.appName)"
    }

    private var normalizedWebDomain: String {
        guard let domain = engine.appMonitor.webAppDomain else {
            return "None"
        }
        return DomainNormalizer.normalizedDomain(for: domain)
    }

    private var eventTapEnabledBinding: Binding<Bool> {
        Binding(
            get: { engine.eventTap.isEnabled },
            set: { engine.eventTap.isEnabled = $0 }
        )
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
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
