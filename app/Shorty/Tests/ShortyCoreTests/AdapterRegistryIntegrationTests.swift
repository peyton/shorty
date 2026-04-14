import Foundation
import XCTest
@testable import ShortyCore

final class AdapterRegistryIntegrationTests: XCTestCase {

    func testUserAdapterOverridesBuiltInAdapterFromDisk() throws {
        let appSupport = temporaryDirectory()
        let userAdapters = appSupport
            .appendingPathComponent("Shorty", isDirectory: true)
            .appendingPathComponent("Adapters", isDirectory: true)
        try FileManager.default.createDirectory(
            at: userAdapters,
            withIntermediateDirectories: true
        )

        let override = Adapter(
            appIdentifier: "com.microsoft.VSCode",
            appName: "VS Code User Override",
            source: .user,
            mappings: [
                .init(canonicalID: "command_palette", method: .passthrough)
            ]
        )
        let data = try JSONEncoder.pretty.encode(override)
        try data.write(to: userAdapters.appendingPathComponent("vscode.json"))

        let registry = AdapterRegistry(appSupportDirectory: appSupport)
        let commandPalette = CanonicalShortcut.defaults.first {
            $0.id == "command_palette"
        }!

        XCTAssertEqual(registry.adapter(for: "com.microsoft.VSCode")?.source, .user)
        XCTAssertEqual(
            registry.resolve(
                combo: commandPalette.defaultKeys,
                forApp: "com.microsoft.VSCode"
            ),
            .passthrough
        )
    }

    func testInvalidUserAdaptersAreSkippedWithoutBlockingValidAdapters() throws {
        let appSupport = temporaryDirectory()
        let userAdapters = appSupport
            .appendingPathComponent("Shorty", isDirectory: true)
            .appendingPathComponent("Adapters", isDirectory: true)
        try FileManager.default.createDirectory(
            at: userAdapters,
            withIntermediateDirectories: true
        )

        let valid = Adapter(
            appIdentifier: "com.shorty.valid.fixture",
            appName: "Valid Fixture",
            source: .user,
            mappings: [
                .init(
                    canonicalID: "select_all",
                    method: .keyRemap,
                    nativeKeys: KeyCombo(from: "cmd+a")
                )
            ]
        )
        let invalid = Adapter(
            appIdentifier: "com.shorty.invalid.fixture",
            appName: "Invalid Fixture",
            source: .user,
            mappings: [
                .init(canonicalID: "missing_shortcut", method: .passthrough)
            ]
        )

        try JSONEncoder.pretty
            .encode(valid)
            .write(to: userAdapters.appendingPathComponent("valid.json"))
        try JSONEncoder.pretty
            .encode(invalid)
            .write(to: userAdapters.appendingPathComponent("invalid.json"))

        let registry = AdapterRegistry(appSupportDirectory: appSupport)

        XCTAssertNotNil(registry.adapter(for: "com.shorty.valid.fixture"))
        XCTAssertNil(registry.adapter(for: "com.shorty.invalid.fixture"))
        XCTAssertTrue(
            registry.validationMessages.contains {
                $0.contains("invalid.json") && $0.contains("unknown canonical")
            },
            "Expected invalid adapter validation message, got \(registry.validationMessages)"
        )
    }

    func testOversizedAdapterFilesAreSkipped() throws {
        let appSupport = temporaryDirectory()
        let userAdapters = appSupport
            .appendingPathComponent("Shorty", isDirectory: true)
            .appendingPathComponent("Adapters", isDirectory: true)
        try FileManager.default.createDirectory(
            at: userAdapters,
            withIntermediateDirectories: true
        )
        let oversized = Data(
            repeating: UInt8(ascii: "x"),
            count: AdapterRegistry.maxAdapterFileSize + 1
        )
        try oversized.write(to: userAdapters.appendingPathComponent("large.json"))

        let registry = AdapterRegistry(appSupportDirectory: appSupport)

        XCTAssertTrue(
            registry.validationMessages.contains {
                $0.contains("large.json") && $0.contains("too large")
            },
            "Expected oversized adapter validation message, got \(registry.validationMessages)"
        )
    }

    func testAdapterValidationRejectsWhitespaceInAppIdentifier() {
        let adapter = Adapter(
            appIdentifier: " com.shorty.invalid.fixture ",
            appName: "Invalid Fixture",
            source: .user,
            mappings: [
                .init(canonicalID: "select_all", method: .passthrough)
            ]
        )

        XCTAssertThrowsError(try AdapterRegistry.validate(adapter: adapter)) { error in
            XCTAssertEqual(
                error as? AdapterValidationError,
                .invalidAppIdentifier(" com.shorty.invalid.fixture ")
            )
        }
    }

    func testSavingUserAdapterUsesSafeFilenameAndUpdatesResolver() throws {
        let appSupport = temporaryDirectory()
        let registry = AdapterRegistry(appSupportDirectory: appSupport)
        let adapter = Adapter(
            appIdentifier: "web:fixture.example",
            appName: "Fixture Web App",
            source: .user,
            mappings: [
                .init(
                    canonicalID: "find_in_page",
                    method: .keyRemap,
                    nativeKeys: KeyCombo(from: "cmd+g")
                )
            ]
        )

        try registry.saveUserAdapter(adapter)

        let adapterPath = appSupport
            .appendingPathComponent("Shorty", isDirectory: true)
            .appendingPathComponent("Adapters", isDirectory: true)
            .appendingPathComponent("web_fixture.example.json")
        let findInPage = CanonicalShortcut.defaults.first {
            $0.id == "find_in_page"
        }!

        XCTAssertTrue(FileManager.default.fileExists(atPath: adapterPath.path))
        XCTAssertEqual(
            registry.resolve(
                combo: findInPage.defaultKeys,
                forApp: "web:fixture.example"
            ),
            .remap(KeyCombo(from: "cmd+g")!)
        )
    }

    func testAllBuiltInAdaptersValidateAndResolveTheirMappings() throws {
        let registry = AdapterRegistry(appSupportDirectory: temporaryDirectory())
        let shortcutsByID = Dictionary(
            uniqueKeysWithValues: CanonicalShortcut.defaults.map { ($0.id, $0) }
        )

        for adapter in AdapterRegistry.builtinAdapters {
            XCTAssertNoThrow(try AdapterRegistry.validate(adapter: adapter))
            for mapping in adapter.mappings {
                let shortcut = try XCTUnwrap(
                    shortcutsByID[mapping.canonicalID],
                    "Missing canonical shortcut for \(mapping.canonicalID)"
                )
                XCTAssertNotNil(
                    registry.resolve(
                        combo: shortcut.defaultKeys,
                        forApp: adapter.appIdentifier
                    ),
                    "Expected \(adapter.appIdentifier) to resolve \(mapping.canonicalID)"
                )
            }
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ShortyRegistryTests-\(UUID().uuidString)",
                isDirectory: true
            )
    }
}
