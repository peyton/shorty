import AppKit
import ShortyCore
import SwiftUI
import XCTest
@testable import Shorty

@MainActor
final class StatusBarPopoverTests: XCTestCase {
    func testSnapshotStoreUpdatesShortcutsWhenActiveAppChanges() {
        let engine = makeEngine()
        let store = StatusBarSnapshotStore(engine: engine)

        engine.appMonitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 501
        )

        XCTAssertTrue(waitFor {
            store.snapshot.activeContextTitle == "Safari" &&
                store.snapshot.availability.state == .available
        })
        XCTAssertEqual(store.snapshot.effectiveID, "com.apple.Safari")
        XCTAssertEqual(store.snapshot.availability.adapterName, "Safari")
        XCTAssertTrue(store.snapshot.availability.shortcuts.contains {
            $0.id == "focus_url_bar"
        })
    }

    func testSnapshotStoreKeepsLastRealAppWhenShortyBecomesActive() {
        let engine = makeEngine()
        let store = StatusBarSnapshotStore(engine: engine)

        engine.appMonitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 601
        )
        XCTAssertTrue(waitFor {
            store.snapshot.activeContextTitle == "Safari"
        })

        XCTAssertFalse(engine.appMonitor.updateActiveApplication(
            bundleIdentifier: "app.peyton.shorty",
            localizedName: "Shorty",
            processIdentifier: 602
        ))

        XCTAssertEqual(store.snapshot.activeContextTitle, "Safari")
        XCTAssertEqual(store.snapshot.effectiveID, "com.apple.Safari")
        XCTAssertEqual(store.snapshot.availability.state, .available)
    }

    func testStatusBarContentRendersAvailableShortcutsWithoutInteraction() {
        let snapshot = makeSnapshot(
            appID: "com.apple.Safari",
            appName: "Safari"
        )

        let rendered = render(
            StatusBarContentView(
                snapshot: snapshot,
                eventTapEnabled: .constant(true)
            )
        )
        let text = rendered.accessibilityText()

        XCTAssertContains(text, "Safari")
        XCTAssertContains(text, "Available now")
        XCTAssertContains(text, "13 available")
        XCTAssertContains(text, "Focus URL / Address Bar")
        XCTAssertContains(text, "Go Back")
        XCTAssertFalse(text.contains("No shortcuts for this app yet"), text)
    }

    func testStatusBarContentRendersNoAdapterRecoveryAction() {
        let snapshot = makeSnapshot(
            appID: "com.example.notes",
            appName: "Acme Notes"
        )

        let rendered = render(
            StatusBarContentView(
                snapshot: snapshot,
                eventTapEnabled: .constant(true)
            )
        )
        let text = rendered.accessibilityText()

        XCTAssertContains(text, "Acme Notes")
        XCTAssertContains(text, "No shortcuts for this app yet")
        XCTAssertContains(text, "Add Current App")
        XCTAssertFalse(text.contains("Focus URL / Address Bar"), text)
    }

    private func makeEngine() -> ShortcutEngine {
        let suiteName = "ShortyPopoverTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }

        return ShortcutEngine(
            configuration: EngineConfiguration(
                startsEventTap: false,
                startsBrowserBridge: false
            ),
            userDefaults: defaults,
            safariExtensionUserDefaults: defaults
        )
    }

    private func makeSnapshot(
        appID: String,
        appName: String
    ) -> StatusBarSnapshot {
        let availability = AdapterRegistry(
            appSupportDirectory: temporaryDirectory()
        ).availability(
            for: appID,
            displayName: appName
        )

        return StatusBarSnapshot(
            status: EngineDisplayStatus.make(
                status: .running,
                permissionState: .granted,
                eventTapEnabled: true,
                isWaitingForPermission: false
            ),
            currentAppName: appName,
            activeContextTitle: appName,
            availability: availability,
            lifecycleMessage: nil,
            effectiveID: appID,
            adapterSource: availability.adapterSource?.statusLabelForTests ?? "none",
            mappingCount: "\(availability.shortcuts.count)",
            webDomain: "None",
            browserContextSource: "No browser context",
            bridgeStatus: "Unavailable",
            safariExtensionStatus: "Safari extension bundled",
            shortcutReviewCount: 0,
            eventsIntercepted: 0,
            eventsMatched: 0,
            eventsRemapped: 0,
            eventsPassedThrough: 0,
            menuActionsInvoked: 0,
            accessibilityActionsInvoked: 0,
            contextGuardsApplied: 0,
            validationMessages: [],
            adapterGenerationMessage: nil,
            hasGeneratedAdapterPreview: false
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortyPopoverTests-\(UUID().uuidString)")
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize = CGSize(width: 430, height: 640)
    ) -> RenderedView {
        let hostingView = NSHostingView(
            rootView: content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light)
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        return RenderedView(window: window, rootView: hostingView)
    }

    private func waitFor(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(
                mode: .default,
                before: Date().addingTimeInterval(0.01)
            )
        }
        return condition()
    }

    private func XCTAssertContains(
        _ text: String,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            text.contains(expected),
            "Expected rendered accessibility text to contain '\(expected)'. Text: \(text)",
            file: file,
            line: line
        )
    }
}

private final class RenderedView {
    let window: NSWindow
    let rootView: NSView

    init(window: NSWindow, rootView: NSView) {
        self.window = window
        self.rootView = rootView
    }

    func accessibilityText() -> String {
        var visited = Set<ObjectIdentifier>()
        return collectAccessibilityText(from: rootView, visited: &visited)
            .joined(separator: "\n")
    }

    private func collectAccessibilityText(
        from element: Any,
        visited: inout Set<ObjectIdentifier>
    ) -> [String] {
        guard let object = element as? NSObject else { return [] }
        let identifier = ObjectIdentifier(object)
        guard visited.insert(identifier).inserted else { return [] }

        var result: [String] = []

        if let view = object as? NSView {
            result.append(
                contentsOf: accessibilityText(
                    label: view.accessibilityLabel(),
                    title: view.accessibilityTitle(),
                    value: view.accessibilityValue(),
                    identifier: view.accessibilityIdentifier()
                )
            )
            for child in view.accessibilityChildren() ?? [] {
                result.append(
                    contentsOf: collectAccessibilityText(
                        from: child,
                        visited: &visited
                    )
                )
            }
            for subview in view.subviews {
                result.append(
                    contentsOf: collectAccessibilityText(
                        from: subview,
                        visited: &visited
                    )
                )
            }
        } else if let element = object as? NSAccessibilityElement {
            result.append(
                contentsOf: accessibilityText(
                    label: element.accessibilityLabel(),
                    title: element.accessibilityTitle(),
                    value: element.accessibilityValue(),
                    identifier: element.accessibilityIdentifier()
                )
            )
            for child in element.accessibilityChildren() ?? [] {
                result.append(
                    contentsOf: collectAccessibilityText(
                        from: child,
                        visited: &visited
                    )
                )
            }
        }

        return result
    }

    private func accessibilityText(
        label: String?,
        title: String?,
        value: Any?,
        identifier: String?
    ) -> [String] {
        [
            label,
            title,
            value as? String,
            identifier
        ].compactMap { text in
            guard let text, !text.isEmpty else { return nil }
            return text
        }
    }
}

private extension Adapter.Source {
    var statusLabelForTests: String {
        switch self {
        case .builtin:
            return "Built-in"
        case .menuIntrospection, .llmGenerated:
            return "Generated"
        case .community:
            return "Community"
        case .user:
            return "User"
        }
    }
}
