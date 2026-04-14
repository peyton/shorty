import AppKit
import ShortyCore
import SwiftUI

final class ShortyAppDelegate: NSObject, NSApplicationDelegate {
    let engine = ShortcutEngine(configuration: ShortyAppDelegate.appConfiguration)
    private var didOpenFirstRunSettings = false

    private static var appConfiguration: EngineConfiguration {
#if SHORTY_APP_STORE
        return .appStoreCandidate
#else
        return .releaseDefault
#endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        engine.start()
        openFirstRunSettingsIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        engine.refreshDailyStatuses()
    }

    private func openFirstRunSettingsIfNeeded() {
        guard !didOpenFirstRunSettings, !engine.isFirstRunComplete else { return }
        didOpenFirstRunSettings = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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
            .accessibilityLabel(engine.status.title)
            .help(engine.status.title)
    }
}
