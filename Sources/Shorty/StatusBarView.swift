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
                HStack {
                    Text("Active app:")
                        .foregroundColor(.secondary)
                    Text(engine.appMonitor.currentAppName ?? "—")
                        .fontWeight(.medium)
                }
                .font(.caption)

                HStack(spacing: 16) {
                    StatView(label: "Intercepted",
                             value: engine.eventTap.eventsIntercepted)
                    StatView(label: "Remapped",
                             value: engine.eventTap.eventsRemapped)
                }
            }

            Divider()

            // Controls
            Toggle("Enabled", isOn: $engine.eventTap.isEnabled)
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
        .frame(width: 280)
        .onAppear {
            if !engine.isRunning {
                engine.start()
            }
        }
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
