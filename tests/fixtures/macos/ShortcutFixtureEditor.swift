import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var textView: NSTextView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMenus()
        configureWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMenus() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Shorty Fixture Editor")
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "Quit Shorty Fixture Editor",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        let newDocument = fileMenu.addItem(
            withTitle: "New Fixture Document",
            action: #selector(newFixtureDocument(_:)),
            keyEquivalent: "n"
        )
        newDocument.target = self

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        let selectAll = editMenu.addItem(
            withTitle: "Select All",
            action: #selector(selectAllFixtureText(_:)),
            keyEquivalent: "a"
        )
        selectAll.target = self
        let findFixtureText = editMenu.addItem(
            withTitle: "Find Fixture Text",
            action: #selector(findFixtureText(_:)),
            keyEquivalent: "f"
        )
        findFixtureText.target = self

        let goMenuItem = NSMenuItem()
        mainMenu.addItem(goMenuItem)
        let goMenu = NSMenu(title: "Go")
        goMenuItem.submenu = goMenu
        let openQuickly = goMenu.addItem(
            withTitle: "Open Quickly",
            action: #selector(openQuickly(_:)),
            keyEquivalent: "o"
        )
        openQuickly.keyEquivalentModifierMask = [.command, .shift]
        openQuickly.target = self
    }

    private func configureWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Shorty Fixture Editor"
        window.center()

        let scrollView = NSScrollView(frame: window.contentView?.bounds ?? .zero)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        let textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.string = "Shorty fixture text. Use menus to test shortcut discovery."
        scrollView.documentView = textView

        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.textView = textView
    }

    @objc private func newFixtureDocument(_ sender: Any?) {
        textView?.string = "New fixture document created."
    }

    @objc private func selectAllFixtureText(_ sender: Any?) {
        textView?.selectAll(sender)
    }

    @objc private func findFixtureText(_ sender: Any?) {
        textView?.string = "Find Fixture Text menu item was invoked."
    }

    @objc private func openQuickly(_ sender: Any?) {
        textView?.string = "Open Quickly menu item was invoked."
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
