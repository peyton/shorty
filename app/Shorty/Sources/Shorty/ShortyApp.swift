import AppKit
import ShortyCore
import SwiftUI

final class ShortyAppDelegate: NSObject, NSApplicationDelegate {
    let engine = ShortcutEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        engine.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }
}

@main
struct ShortyApp: App {
    @NSApplicationDelegateAdaptor(ShortyAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusBarView(engine: appDelegate.engine)
        } label: {
            StatusIconView(engine: appDelegate.engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: appDelegate.engine)
        }
    }
}

private struct StatusIconView: View {
    @ObservedObject var engine: ShortcutEngine

    var body: some View {
        Image(systemName: iconName)
    }

    private var iconName: String {
        switch engine.status {
        case .running:
            return "keyboard.fill"
        case .disabled:
            return "keyboard"
        case .permissionRequired, .failed:
            return "exclamationmark.triangle.fill"
        case .stopped, .starting:
            return "keyboard"
        }
    }
}
