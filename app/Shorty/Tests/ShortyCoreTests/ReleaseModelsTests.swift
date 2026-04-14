import Foundation
import XCTest
@testable import ShortyCore

final class ReleaseModelsTests: XCTestCase {
    func testShortcutProfileDetectsDuplicateKeyConflicts() {
        let shortcuts = [
            CanonicalShortcut(
                id: "one",
                name: "One",
                defaultKeys: KeyCombo(keyCode: 0x00, modifiers: .command),
                category: .editing,
                description: "First"
            ),
            CanonicalShortcut(
                id: "two",
                name: "Two",
                defaultKeys: KeyCombo(keyCode: 0x00, modifiers: .command),
                category: .editing,
                description: "Second"
            )
        ]

        let conflicts = UserShortcutProfile(shortcuts: shortcuts).conflicts()

        XCTAssertTrue(conflicts.contains { conflict in
            conflict.kind == .duplicateKeyCombo
                && conflict.shortcutIDs == ["one", "two"]
        })
    }

    func testShortcutProfileFlagsContextSensitiveDefaults() {
        let conflicts = UserShortcutProfile.releaseDefault.conflicts()

        XCTAssertTrue(conflicts.contains { $0.shortcutIDs == ["submit_field"] })
        XCTAssertTrue(conflicts.contains { $0.shortcutIDs == ["newline_in_field"] })
    }

    func testSupportBundleEncodesStableJSON() throws {
        let diagnostics = RuntimeDiagnosticSnapshot(
            engineStatus: "Shorty is active",
            permissionState: .granted,
            currentAppName: "Safari",
            currentBundleID: "com.apple.Safari",
            effectiveAppID: "web:figma.com",
            browserContextSource: .safariExtension,
            webDomain: "figma.com",
            bridgeStatus: "Browser bridge stopped",
            safariExtensionStatus: SafariExtensionStatus(
                state: .enabled,
                bundleIdentifier: "app.peyton.shorty.SafariWebExtension",
                lastMessageAt: Date(timeIntervalSince1970: 10),
                lastDomain: "figma.com",
                detail: "Safari reported figma.com."
            ),
            eventsIntercepted: 4,
            eventsRemapped: 2,
            adapterValidationMessages: []
        )
        let bundle = SupportBundle(
            diagnostics: diagnostics,
            shortcutProfile: .releaseDefault,
            adapters: ["web:figma.com"]
        )

        let json = try XCTUnwrap(String(data: bundle.encodedJSON(), encoding: .utf8))

        XCTAssertTrue(json.contains(#""browserContextSource" : "safariExtension""#))
        XCTAssertTrue(json.contains(#""web:figma.com""#))
    }

    func testShortcutEngineDiagnosticSnapshotIncludesBrowserSource() {
        let suiteName = "ShortyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let engine = ShortcutEngine(
            userDefaults: defaults,
            safariExtensionUserDefaults: defaults
        )

        engine.appMonitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 501
        )
        engine.recordSafariExtensionMessage(domain: "www.figma.com")

        let snapshot = engine.diagnosticSnapshot()

        XCTAssertEqual(snapshot.browserContextSource, .safariExtension)
        XCTAssertEqual(snapshot.webDomain, "figma.com")
        XCTAssertEqual(snapshot.effectiveAppID, "web:figma.com")
        XCTAssertEqual(engine.safariExtensionStatus.state, .enabled)
    }

    func testSafariExtensionBridgeMessageRefreshClearsDomain() throws {
        let suiteName = "ShortyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let message = SafariExtensionBridgeMessage(kind: .domainCleared)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(
            try encoder.encode(message),
            forKey: SafariExtensionBridge.lastMessageDefaultsKey
        )
        let engine = ShortcutEngine(
            userDefaults: defaults,
            safariExtensionUserDefaults: defaults
        )

        engine.appMonitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 501
        )
        engine.appMonitor.updateBrowserContext(
            domain: "linear.app",
            source: .safariExtension
        )

        engine.refreshSafariExtensionMessage()

        XCTAssertNil(engine.appMonitor.webAppDomain)
        XCTAssertEqual(engine.appMonitor.browserContextSource, .none)
        XCTAssertEqual(engine.safariExtensionStatus.state, .enabled)
    }

}
