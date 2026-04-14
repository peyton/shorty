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
                .tint(ShortyBrand.teal)
        } label: {
            StatusIconView(engine: appDelegate.engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: appDelegate.engine)
                .tint(ShortyBrand.teal)
        }
    }
}

private struct StatusIconView: View {
    @ObservedObject var engine: ShortcutEngine

    var body: some View {
        ShortyMenuBarGlyph(status: engine.status)
    }
}
