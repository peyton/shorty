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

    func testStatusBarContentPresentsAvailableShortcutsWithoutInteraction() {
        let snapshot = makeSnapshot(
            appID: "com.apple.Safari",
            appName: "Safari"
        )

        let view = StatusBarContentView(
            snapshot: snapshot,
            eventTapEnabled: .constant(true)
        )
        let presentation = view.contentPresentation

        XCTAssertEqual(presentation.activeContextTitle, "Safari")
        XCTAssertEqual(presentation.shortcuts.title, "Available now")
        XCTAssertContains(presentation.shortcuts.coverageDetail, "For Safari")
        XCTAssertEqual(presentation.shortcuts.rows.count, 13)
        XCTAssertTrue(presentation.shortcuts.rows.contains {
            $0.name == "Focus URL / Address Bar"
        })
        XCTAssertTrue(presentation.shortcuts.rows.contains { $0.name == "Go Back" })
        XCTAssertNil(presentation.shortcuts.emptyState)
        XCTAssertTrue(presentation.shortcuts.showsPauseActions)
        XCTAssertFalse(presentation.shortcuts.showsResumeAction)
    }

    func testStatusBarContentPresentsNoAdapterRecoveryAction() {
        let snapshot = makeSnapshot(
            appID: "com.example.notes",
            appName: "Acme Notes"
        )

        let view = StatusBarContentView(
            snapshot: snapshot,
            eventTapEnabled: .constant(true)
        )
        let presentation = view.contentPresentation

        XCTAssertEqual(presentation.activeContextTitle, "Acme Notes")
        XCTAssertContains(
            presentation.shortcuts.coverageDetail,
            "Shorty does not have shortcuts for Acme Notes yet."
        )
        XCTAssertTrue(presentation.shortcuts.rows.isEmpty)
        XCTAssertEqual(
            presentation.shortcuts.emptyState?.title,
            "No shortcuts for this app yet"
        )
        XCTAssertEqual(
            presentation.shortcuts.emptyState?.detail,
            "Shorty will pass keys through until you add support for this app."
        )
        XCTAssertEqual(presentation.shortcuts.emptyState?.showsAddButton, true)
        XCTAssertFalse(presentation.shortcuts.showsPauseActions)
        XCTAssertFalse(presentation.shortcuts.showsResumeAction)
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
            "Expected text to contain '\(expected)'. Text: \(text)",
            file: file,
            line: line
        )
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
