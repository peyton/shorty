import SwiftUI
import ShortyCore

/// The popover view shown when the user clicks the menu bar icon.
struct StatusBarView: View {
    @ObservedObject var engine: ShortcutEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "keyboard.fill")
                    .font(.title2)
                Text("Shorty")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(engine.isRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }

            Divider()

            // Status
            if let error = engine.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)

                Button("Open Accessibility Settings") {
                    ShortcutEngine.requestAccessibilityPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                RuntimeDiagnosticsView(
                    appMonitor: engine.appMonitor,
                    registry: engine.registry,
                    eventTap: engine.eventTap
                )
            }

            Divider()

            // Controls
            Toggle("Enabled", isOn: eventTapEnabledBinding)
                .toggleStyle(.switch)
                .controlSize(.small)

            HStack {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")),
                                     to: nil, from: nil)
                    // Bring our app to front so the settings window is visible.
                    NSApp.activate(ignoringOtherApps: true)
                }

                Spacer()

                Button("Quit") {
                    engine.stop()
                    NSApp.terminate(nil)
                }
            }
        }
        .padding()
        .frame(width: 320)
    }

    private var eventTapEnabledBinding: Binding<Bool> {
        Binding(
            get: { engine.eventTap.isEnabled },
            set: { engine.eventTap.isEnabled = $0 }
        )
    }
}

// MARK: - Runtime diagnostics

private struct RuntimeDiagnosticsView: View {
    @ObservedObject var appMonitor: AppMonitor
    @ObservedObject var registry: AdapterRegistry
    @ObservedObject var eventTap: EventTapManager

    private var adapter: Adapter? {
        guard let appID = appMonitor.effectiveAppID else {
            return nil
        }
        return registry.activeAdapter(for: appID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            diagnosticRow("Active app", appMonitor.currentAppName ?? "—")
            diagnosticRow("Effective ID", appMonitor.effectiveAppID ?? "—")
            diagnosticRow("Adapter", adapter?.appName ?? "Pass through")
            diagnosticRow("Source", adapter?.source.rawValue ?? "none")
            diagnosticRow("Mappings", adapter.map { "\($0.mappings.count)" } ?? "0")
            diagnosticRow("Web domain", normalizedWebDomain)

            HStack(spacing: 16) {
                StatView(label: "Intercepted",
                         value: eventTap.eventsIntercepted)
                StatView(label: "Remapped",
                         value: eventTap.eventsRemapped)
            }
            .padding(.top, 2)
        }
    }

    private var normalizedWebDomain: String {
        guard let domain = appMonitor.webAppDomain else {
            return "—"
        }
        return DomainNormalizer.normalizedDomain(for: domain)
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text("\(label):")
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

// MARK: - Stat view helper

private struct StatView: View {
    let label: String
    let value: Int

    var body: some View {
        VStack {
            Text("\(value)")
                .font(.title3.monospacedDigit())
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
