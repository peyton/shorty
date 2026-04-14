import SwiftUI
import ShortyCore

/// The main entry point for Shorty — a menu-bar-only macOS app.
///
/// We use `MenuBarExtra` (macOS 13+) to place an icon in the system
/// status bar. There is no dock icon or main window.
@main
struct ShortyApp: App {
    @StateObject private var engine = ShortcutEngine()

    var body: some Scene {
        // Menu bar icon + popover
        MenuBarExtra {
            StatusBarView(engine: engine)
        } label: {
            // SF Symbol for keyboard
            Image(systemName: engine.isRunning ? "keyboard.fill" : "keyboard")
                .onAppear {
                    engine.start()
                }
        }
        .menuBarExtraStyle(.window)

        // Settings window (opened from the menu)
        Settings {
            SettingsView(engine: engine)
        }
    }

    init() {
        // Hide dock icon — we're a pure menu-bar app.
        NSApp.setActivationPolicy(.accessory)
    }
}
