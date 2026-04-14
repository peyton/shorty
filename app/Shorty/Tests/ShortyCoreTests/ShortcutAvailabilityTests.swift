import Foundation
import XCTest
@testable import ShortyCore

final class ShortcutAvailabilityTests: XCTestCase {
    func testAvailabilityForKnownAdapterReturnsOrderedShortcuts() throws {
        let registry = makeRegistry()

        let availability = registry.availability(
            for: "com.apple.Safari",
            displayName: "Safari"
        )

        XCTAssertEqual(availability.state, .available)
        XCTAssertEqual(availability.adapterName, "Safari")
        XCTAssertEqual(availability.coverageTitle, "13 available")
        XCTAssertEqual(
            availability.shortcuts.prefix(3).map(\.id),
            ["focus_url_bar", "go_back", "go_forward"]
        )
        XCTAssertEqual(availability.shortcuts.first?.defaultKeys.displayString, "⌘L")
        XCTAssertEqual(availability.shortcuts.first?.actionKind, .passthrough)
    }

    func testAvailabilityWithoutAdapterExplainsPassThrough() {
        let registry = makeRegistry()

        let availability = registry.availability(
            for: "com.example.Unknown",
            displayName: "Unknown App"
        )

        XCTAssertEqual(availability.state, .noAdapter)
        XCTAssertEqual(availability.appDisplayName, "Unknown App")
        XCTAssertEqual(availability.coverageTitle, "Pass through")
        XCTAssertEqual(
            availability.coverageDetail,
            "Shorty does not have shortcuts for Unknown App yet."
        )
        XCTAssertTrue(availability.shortcuts.isEmpty)
    }

    func testAvailabilityWithoutActiveAppHasEmptyState() {
        let registry = makeRegistry()

        let availability = registry.availability(for: nil, displayName: nil)

        XCTAssertEqual(availability.state, .noActiveApp)
        XCTAssertEqual(availability.coverageTitle, "No active app")
        XCTAssertTrue(availability.shortcuts.isEmpty)
    }

    func testAvailabilitySummarizesEveryMappingMethod() throws {
        let registry = makeRegistry()
        let adapter = Adapter(
            appIdentifier: "com.example.Methods",
            appName: "Methods",
            source: .user,
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough),
                .init(
                    canonicalID: "command_palette",
                    method: .keyRemap,
                    nativeKeys: try XCTUnwrap(KeyCombo(from: "cmd+k"))
                ),
                .init(
                    canonicalID: "new_window",
                    method: .menuInvoke,
                    menuTitle: "New Window"
                ),
                .init(
                    canonicalID: "select_all",
                    method: .axAction,
                    axAction: "AXPress"
                )
            ]
        )

        try registry.saveUserAdapter(adapter)

        let availability = registry.availability(
            for: "com.example.Methods",
            displayName: "Methods"
        )
        let shortcuts = Dictionary(
            uniqueKeysWithValues: availability.shortcuts.map { ($0.id, $0) }
        )

        XCTAssertEqual(shortcuts["focus_url_bar"]?.actionKind, .passthrough)
        XCTAssertEqual(
            shortcuts["focus_url_bar"]?.actionDescription,
            "Uses ⌘L in Methods"
        )
        XCTAssertEqual(shortcuts["command_palette"]?.actionKind, .keyRemap)
        XCTAssertEqual(shortcuts["command_palette"]?.actionDescription, "Sends ⌘K")
        XCTAssertEqual(shortcuts["new_window"]?.actionKind, .menuInvoke)
        XCTAssertEqual(shortcuts["new_window"]?.actionDescription, "Chooses New Window")
        XCTAssertEqual(shortcuts["select_all"]?.actionKind, .axAction)
        XCTAssertEqual(shortcuts["select_all"]?.actionDescription, "Performs AXPress")
    }

    func testAvailabilitySupportsWebIdentifiers() {
        let registry = makeRegistry()

        let availability = registry.availability(
            for: "web:figma.com",
            displayName: "Figma Web in Safari"
        )

        XCTAssertEqual(availability.state, .available)
        XCTAssertEqual(availability.appDisplayName, "Figma Web in Safari")
        XCTAssertEqual(availability.adapterName, "Figma Web")
        XCTAssertTrue(availability.shortcuts.contains { $0.id == "command_palette" })
    }

    func testEngineDisplayStatusUsesPlainLabels() {
        XCTAssertEqual(
            EngineDisplayStatus.make(
                status: .running,
                permissionState: .granted,
                eventTapEnabled: true,
                isWaitingForPermission: false
            ).title,
            "Ready"
        )
        XCTAssertEqual(
            EngineDisplayStatus.make(
                status: .disabled,
                permissionState: .granted,
                eventTapEnabled: false,
                isWaitingForPermission: false
            ).title,
            "Paused"
        )
        XCTAssertEqual(
            EngineDisplayStatus.make(
                status: .permissionRequired,
                permissionState: .notGranted,
                eventTapEnabled: true,
                isWaitingForPermission: false
            ).title,
            "Needs Accessibility access"
        )
        XCTAssertEqual(
            EngineDisplayStatus.make(
                status: .permissionRequired,
                permissionState: .notGranted,
                eventTapEnabled: true,
                isWaitingForPermission: true
            ).title,
            "Waiting for Accessibility access"
        )
        XCTAssertEqual(
            EngineDisplayStatus.make(
                status: .failed("Could not install tap."),
                permissionState: .granted,
                eventTapEnabled: true,
                isWaitingForPermission: false
            ).title,
            "Needs attention"
        )
    }

    private func makeRegistry() -> AdapterRegistry {
        AdapterRegistry(appSupportDirectory: temporaryDirectory())
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortyAvailabilityTests-\(UUID().uuidString)")
    }
}
