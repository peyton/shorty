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

    func testShortcutProfilePersistsCustomizationState() throws {
        var profile = UserShortcutProfile.releaseDefault
        profile.setShortcut("focus_url_bar", enabled: false)
        profile.setAdapter("com.example.App", enabled: false)
        profile.setMapping(
            adapterID: "com.example.App",
            canonicalID: "new_window",
            enabled: false
        )
        profile.updateShortcut(
            "spotlight_search",
            keyCombo: try XCTUnwrap(KeyCombo(from: "cmd+shift+k"))
        )

        let decoded = try UserShortcutProfile.decode(from: profile.encodedJSON())

        XCTAssertFalse(decoded.isShortcutEnabled("focus_url_bar"))
        XCTAssertFalse(decoded.isAdapterEnabled("com.example.App"))
        XCTAssertFalse(decoded.isMappingEnabled(
            adapterID: "com.example.App",
            canonicalID: "new_window"
        ))
        XCTAssertEqual(
            decoded.shortcuts.first { $0.id == "spotlight_search" }?.defaultKeys,
            KeyCombo(from: "cmd+shift+k")
        )
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
            eventsMatched: 3,
            eventsRemapped: 2,
            eventsPassedThrough: 1,
            menuActionsInvoked: 0,
            accessibilityActionsInvoked: 0,
            adapterValidationMessages: []
        )
        let bundle = SupportBundle(
            summary: SupportBundleSummary(
                appVersion: "1.0.0 (1)",
                adapterCount: 1,
                adapterCountsBySource: ["builtin": 1],
                supportedWebDomains: ["figma.com"],
                validationWarningCount: 0,
                activeAvailability: ShortcutAvailability(
                    state: .available,
                    appIdentifier: "web:figma.com",
                    appDisplayName: "Figma Web",
                    adapterIdentifier: "web:figma.com",
                    adapterName: "Figma Web",
                    adapterSource: .builtin
                )
            ),
            diagnostics: diagnostics,
            shortcutProfile: .releaseDefault,
            adapters: ["web:figma.com"]
        )

        let json = try XCTUnwrap(String(data: bundle.encodedJSON(), encoding: .utf8))

        XCTAssertTrue(json.contains(#""adapterCount" : 1"#))
        XCTAssertTrue(json.contains(#""appVersion" : "1.0.0 (1)""#))
        XCTAssertTrue(json.contains(#""browserContextSource" : "safariExtension""#))
        XCTAssertTrue(json.contains(#""eventsMatched" : 3"#))
        XCTAssertTrue(json.contains(#""supportedWebDomains" : ["#))
        XCTAssertTrue(json.contains(#""web:figma.com""#))
    }

    func testUpdateStatusEncodesOpenSourceMetadata() throws {
        let sourceURL = try XCTUnwrap(
            URL(string: "https://github.com/peyton/shorty/releases/tag/v1.0.0")
        )
        let status = UpdateStatus(
            state: .idle,
            lastCheckedAt: Date(timeIntervalSince1970: 20),
            currentVersion: "1.0.0 (1)",
            sourceURL: sourceURL,
            automaticChecksEnabled: true,
            detail: "Updates are ready."
        )

        let data = try JSONEncoder().encode(status)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(status.currentVersion, "1.0.0 (1)")
        XCTAssertEqual(status.sourceURL, sourceURL)
        XCTAssertTrue(json.contains(#""currentVersion":"1.0.0 (1)""#))
        XCTAssertTrue(json.contains(#""sourceURL":"https:\/\/github.com\/peyton\/shorty\/releases\/tag\/v1.0.0""#))
    }

    func testLaunchAtLoginStatusReportsUserFacingState() {
        let enabled = LaunchAtLoginStatus(
            state: .enabled,
            detail: "Shorty will open automatically when you sign in."
        )
        let needsApproval = LaunchAtLoginStatus(
            state: .requiresApproval,
            detail: "Approve Shorty in System Settings."
        )

        XCTAssertTrue(enabled.isEnabled)
        XCTAssertEqual(enabled.title, "Launch at Login enabled")
        XCTAssertFalse(needsApproval.isEnabled)
        XCTAssertEqual(needsApproval.title, "Launch at Login needs approval")
    }

    func testEventTapCountersSeparateObservedMatchedAndActionCounts() {
        var counters = EventTapCounters()

        counters.recordKeyDownEvent()
        counters.recordKeyDownEvent()
        counters.recordResolvedAction(.remap(KeyCombo(from: "cmd+k")!))
        counters.recordResolvedAction(.invokeMenu("New Window"))
        counters.recordAsyncActionResult(kind: .menuInvoke, succeeded: false)
        counters.recordContextGuard()

        XCTAssertEqual(counters.keyDownEventsSeen, 2)
        XCTAssertEqual(counters.shortcutsMatched, 2)
        XCTAssertEqual(counters.eventsRemapped, 1)
        XCTAssertEqual(counters.menuActionsInvoked, 1)
        XCTAssertEqual(counters.menuActionsFailed, 1)
        XCTAssertEqual(counters.eventsPassedThrough, 1)
        XCTAssertEqual(counters.contextGuardsApplied, 1)
    }

    func testAppMonitorExpiresStaleBrowserContext() {
        let monitor = AppMonitor()
        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 401
        )
        monitor.updateBrowserContext(domain: "workspace.slack.com", source: .chromeBridge)

        XCTAssertEqual(monitor.snapshot().effectiveAppID, "web:slack.com")
        XCTAssertTrue(monitor.expireStaleBrowserContext(
            now: Date().addingTimeInterval(AppMonitor.browserContextExpirationInterval + 1)
        ))
        XCTAssertNil(monitor.webAppDomain)
        XCTAssertEqual(monitor.effectiveAppID, "com.google.Chrome")
    }

    func testAdapterMappingDecodesLegacyPayloadWithDefaults() throws {
        let payload = Data(
            #"{"canonicalID":"new_window","method":"menuInvoke","menuTitle":"New Window"}"#.utf8
        )

        let mapping = try JSONDecoder().decode(Adapter.Mapping.self, from: payload)

        XCTAssertTrue(mapping.isEnabled)
        XCTAssertNil(mapping.menuPath)
        XCTAssertNil(mapping.matchReason)
    }

    func testBridgeInstallManagerReportsInstalledManifest() throws {
        let home = temporaryDirectory()
        let manager = BrowserBridgeInstallManager(homeDirectory: home)
        let manifestDirectory = home
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        try FileManager.default.createDirectory(
            at: manifestDirectory,
            withIntermediateDirectories: true
        )
        let helper = home.appendingPathComponent("shorty-bridge")
        try "#!/bin/sh\nexit 0\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helper.path
        )
        let manifest = manifestDirectory
            .appendingPathComponent("\(BrowserBridgeInstallManager.nativeHostName).json")
        let payload: [String: Any] = [
            "name": BrowserBridgeInstallManager.nativeHostName,
            "description": "Shorty browser context bridge",
            "path": helper.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: manifest)

        let status = manager.status(for: .chrome)

        XCTAssertEqual(status.state, .installed)
        XCTAssertEqual(status.manifestPath, manifest.path)
        XCTAssertEqual(status.helperPath, helper.path)
    }

    func testBridgeInstallManagerFlagsMissingHelper() throws {
        let home = temporaryDirectory()
        let manager = BrowserBridgeInstallManager(homeDirectory: home)
        let manifestDirectory = home
            .appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts")
        try FileManager.default.createDirectory(
            at: manifestDirectory,
            withIntermediateDirectories: true
        )
        let manifest = manifestDirectory
            .appendingPathComponent("\(BrowserBridgeInstallManager.nativeHostName).json")
        let payload: [String: Any] = [
            "name": BrowserBridgeInstallManager.nativeHostName,
            "path": home.appendingPathComponent("missing-helper").path
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try data.write(to: manifest)

        let status = manager.status(for: .brave)

        XCTAssertEqual(status.state, .needsAttention)
        XCTAssertTrue(status.detail.contains("missing or not executable"))
    }

    func testGeneratedAdapterReviewExplainsConfidenceAndWarnings() throws {
        let adapter = Adapter(
            appIdentifier: "com.example.Generated",
            appName: "Generated",
            source: .menuIntrospection,
            mappings: [
                .init(canonicalID: "submit_field", method: .menuInvoke, menuTitle: "Send"),
                .init(
                    canonicalID: "command_palette",
                    method: .keyRemap,
                    nativeKeys: try XCTUnwrap(KeyCombo(from: "cmd+k"))
                )
            ]
        )

        let review = ShortcutEngine.reviewGeneratedAdapter(adapter)

        XCTAssertEqual(review.adapterIdentifier, adapter.appIdentifier)
        XCTAssertFalse(review.reasons.isEmpty)
        XCTAssertTrue(review.warnings.contains { $0.contains("text-entry") })
        XCTAssertGreaterThan(review.confidence, 0)
        XCTAssertLessThanOrEqual(review.confidence, 0.98)
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

    func testShortcutEngineSupportBundleIncludesSummaryMetadata() {
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
        engine.recordSafariExtensionMessage(domain: "docs.google.com")

        let bundle = engine.supportBundle()

        XCTAssertEqual(bundle.summary.adapterCount, bundle.adapters.count)
        XCTAssertGreaterThan(bundle.summary.adapterCountsBySource["builtin"] ?? 0, 0)
        XCTAssertTrue(bundle.summary.supportedWebDomains.contains("docs.google.com"))
        XCTAssertFalse(bundle.summary.bridgeInstallStatuses.isEmpty)
        XCTAssertEqual(bundle.summary.activeAvailability.state, .available)
        XCTAssertEqual(bundle.summary.activeAvailability.adapterIdentifier, "web:docs.google.com")
    }

    func testShortcutEngineLoadsPersistedAdapterRevisions() throws {
        let suiteName = "ShortyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let adapter = Adapter(
            appIdentifier: "com.example.persisted-adapter",
            appName: "Persisted Adapter",
            source: .user,
            mappings: [.init(canonicalID: "new_window", method: .passthrough)]
        )
        let revision = AdapterRevision(
            adapterIdentifier: adapter.appIdentifier,
            summary: "Imported user adapter.",
            adapter: adapter
        )
        defaults.set(
            try JSONEncoder().encode([revision]),
            forKey: ShortcutEngine.adapterRevisionsDefaultsKey
        )

        let engine = ShortcutEngine(
            userDefaults: defaults,
            safariExtensionUserDefaults: defaults
        )

        XCTAssertEqual(engine.adapterRevisions.count, 1)
        XCTAssertEqual(engine.adapterRevisions.first?.adapterIdentifier, adapter.appIdentifier)
    }

    func testGeneratedAdapterReviewFlagsLowCoverageAndRiskyMappings() throws {
        let adapter = Adapter(
            appIdentifier: "com.shorty.generated.fixture",
            appName: "Generated Fixture",
            source: .menuIntrospection,
            mappings: [
                .init(canonicalID: "submit_field", method: .passthrough),
                .init(
                    canonicalID: "new_window",
                    method: .menuInvoke,
                    menuTitle: "New Window"
                )
            ]
        )

        let review = ShortcutEngine.reviewGeneratedAdapter(adapter)

        XCTAssertEqual(review.adapterIdentifier, adapter.appIdentifier)
        XCTAssertLessThan(review.confidence, 0.75)
        XCTAssertTrue(review.warnings.contains { $0.contains("Low coverage") })
        XCTAssertTrue(review.warnings.contains { $0.contains("text-entry") })
        XCTAssertTrue(review.warnings.contains { $0.contains("Menu-invoked") })
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

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ShortyReleaseModelTests-\(UUID().uuidString)", isDirectory: true)
}
