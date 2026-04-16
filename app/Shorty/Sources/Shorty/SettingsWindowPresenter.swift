import AppKit
import ShortyCore
import SwiftUI

final class SettingsWindowPresenter {
    private let engine: ShortcutEngine
    private var windowController: NSWindowController?

    init(engine: ShortcutEngine) {
        self.engine = engine
    }

    func show() {
        let window = windowController?.window ?? makeWindow()
        if windowController?.window == nil {
            windowController = NSWindowController(window: window)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let controller = NSHostingController(
            rootView: SettingsView(engine: engine)
                .tint(ShortyBrand.teal)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shorty Settings"
        window.identifier = NSUserInterfaceItemIdentifier("shorty-settings-window")
        window.contentViewController = controller
        window.minSize = NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
