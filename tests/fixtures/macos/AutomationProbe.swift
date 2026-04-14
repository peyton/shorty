import AppKit
import ApplicationServices
import Foundation

private let arguments = CommandLine.arguments

guard arguments.count >= 3 else {
    fail("usage: AutomationProbe <app-path> <bundle-id> [--require-ui-scripting]", code: 64)
}

let appURL = URL(fileURLWithPath: arguments[1])
let expectedBundleID = arguments[2]
let requireUIScripting = arguments.contains("--require-ui-scripting")

let launchedApp = launchFixture(at: appURL)
defer {
    terminate(launchedApp)
}

guard waitForFrontmostBundleID(expectedBundleID) else {
    let actual = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    fail("expected \(expectedBundleID) to become frontmost; got \(actual)")
}

note("activated \(expectedBundleID)")

let trusted = AXIsProcessTrustedWithOptions([
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
] as CFDictionary)

guard trusted else {
    if requireUIScripting {
        fail("Accessibility permission is required for UI scripting checks", code: 2)
    }
    note("ui-scripting skipped: Accessibility permission is not granted")
    exit(0)
}

let menuTitles = collectMenuTitles(for: launchedApp.processIdentifier)
for expected in [
    "File",
    "Edit",
    "Go",
    "New Fixture Document",
    "Select All",
    "Find Fixture Text",
    "Open Quickly"
] where !menuTitles.contains(expected) {
    fail("missing expected menu title: \(expected)")
}

note("ui-scripting verified fixture menus")

private func launchFixture(at appURL: URL) -> NSRunningApplication {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = true

    let semaphore = DispatchSemaphore(value: 0)
    var launchedApp: NSRunningApplication?
    var launchError: Error?

    NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
        launchedApp = app
        launchError = error
        semaphore.signal()
    }

    while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }

    if let launchError {
        fail("could not launch fixture app: \(launchError.localizedDescription)")
    }

    guard let launchedApp else {
        fail("could not launch fixture app")
    }

    launchedApp.activate(options: [.activateAllWindows])
    return launchedApp
}

private func waitForFrontmostBundleID(_ bundleID: String) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID {
            return true
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return false
}

private func collectMenuTitles(for pid: pid_t) -> Set<String> {
    let appElement = AXUIElementCreateApplication(pid)
    guard let menuBar = copyElementAttribute(
        appElement,
        attribute: kAXMenuBarAttribute as CFString
    ) else {
        fail("could not read fixture menu bar")
    }

    var titles = Set<String>()
    collectTitles(from: menuBar, into: &titles)
    return titles
}

private func collectTitles(from element: AXUIElement, into titles: inout Set<String>) {
    if let title = copyStringAttribute(element, attribute: kAXTitleAttribute as CFString),
       !title.isEmpty {
        titles.insert(title)
    }

    guard let children = copyElementArrayAttribute(
        element,
        attribute: kAXChildrenAttribute as CFString
    ) else {
        return
    }

    for child in children {
        collectTitles(from: child, into: &titles)
    }
}

private func copyElementAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
          let value
    else {
        return nil
    }
    return unsafeBitCast(value, to: AXUIElement.self)
}

private func copyElementArrayAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> [AXUIElement]? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return value as? [AXUIElement]
}

private func copyStringAttribute(
    _ element: AXUIElement,
    attribute: CFString
) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
        return nil
    }
    return value as? String
}

private func terminate(_ application: NSRunningApplication) {
    guard !application.isTerminated else {
        return
    }

    application.terminate()
    let deadline = Date().addingTimeInterval(2)
    while Date() < deadline {
        if application.isTerminated {
            return
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    application.forceTerminate()
}

private func note(_ message: String) {
    print(message)
}

private func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    exit(code)
}
