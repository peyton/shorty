import XCTest
@testable import ShortyCore

final class KeyComboTests: XCTestCase {

    // MARK: - Modifier parsing

    func testModifierParsing() {
        let combo = KeyCombo(from: "cmd+shift+c")
        XCTAssertNotNil(combo)
        XCTAssertTrue(combo!.modifiers.contains(.command))
        XCTAssertTrue(combo!.modifiers.contains(.shift))
        XCTAssertFalse(combo!.modifiers.contains(.option))
        XCTAssertFalse(combo!.modifiers.contains(.control))
    }

    func testSingleModifier() {
        let combo = KeyCombo(from: "cmd+v")
        XCTAssertNotNil(combo)
        XCTAssertEqual(combo!.modifiers, .command)
    }

    func testAllModifiers() {
        let combo = KeyCombo(from: "cmd+shift+opt+ctrl+a")
        XCTAssertNotNil(combo)
        XCTAssertTrue(combo!.modifiers.contains(.command))
        XCTAssertTrue(combo!.modifiers.contains(.shift))
        XCTAssertTrue(combo!.modifiers.contains(.option))
        XCTAssertTrue(combo!.modifiers.contains(.control))
    }

    func testInvalidString() {
        let combo = KeyCombo(from: "")
        XCTAssertNil(combo)
    }

    func testAlternateModifierNames() {
        let combo = KeyCombo(from: "command+option+control+t")
        XCTAssertNotNil(combo)
        XCTAssertTrue(combo!.modifiers.contains(.command))
        XCTAssertTrue(combo!.modifiers.contains(.option))
        XCTAssertTrue(combo!.modifiers.contains(.control))
    }

    // MARK: - KeyCodeMap

    func testKeyCodeMapRoundTrip() {
        // "c" should resolve to keycode 8
        let code = KeyCodeMap.keyCode(for: "c")
        XCTAssertEqual(code, 8)

        let name = KeyCodeMap.keyName(for: 8)
        XCTAssertEqual(name, "c")
    }

    func testSpecialKeys() {
        XCTAssertNotNil(KeyCodeMap.keyCode(for: "return"))
        XCTAssertNotNil(KeyCodeMap.keyCode(for: "tab"))
        XCTAssertNotNil(KeyCodeMap.keyCode(for: "escape"))
        XCTAssertNotNil(KeyCodeMap.keyCode(for: "space"))
    }

    // MARK: - Description round-trip

    func testDescriptionFormat() {
        let combo = KeyCombo(from: "cmd+shift+l")!
        // description should contain all parts
        let desc = combo.description
        XCTAssertTrue(desc.contains("cmd"), "Description should contain 'cmd', got: \(desc)")
        XCTAssertTrue(desc.contains("shift"), "Description should contain 'shift', got: \(desc)")
        XCTAssertTrue(desc.contains("l"), "Description should contain 'l', got: \(desc)")
    }

    // MARK: - Equality

    func testKeyComboEquality() {
        let a = KeyCombo(from: "cmd+c")
        let b = KeyCombo(keyCode: 8, modifiers: .command)
        XCTAssertEqual(a, b)
    }

    // MARK: - CanonicalShortcut defaults

    func testDefaultShortcutsExist() {
        let shortcuts = CanonicalShortcut.defaults
        XCTAssertFalse(shortcuts.isEmpty)
    }

    func testEveryDefaultHasKeyCombo() {
        for shortcut in CanonicalShortcut.defaults {
            // defaultKeys is non-optional, so this is really
            // testing that keyCode isn't something wild.
            XCTAssertTrue(
                shortcut.defaultKeys.keyCode < 0xFF,
                "\(shortcut.id) has suspicious keycode: \(shortcut.defaultKeys.keyCode)"
            )
        }
    }

    func testFindInPageExists() {
        let find = CanonicalShortcut.defaults.first { $0.id == "find_in_page" }
        XCTAssertNotNil(find)
        XCTAssertEqual(find?.category, .search)
    }

    // MARK: - Adapter

    func testAdapterMappingLookup() {
        let adapter = Adapter(
            appIdentifier: "com.test.app",
            appName: "Test App",
            source: .builtin,
            mappings: [
                Adapter.Mapping(
                    canonicalID: "select_all",
                    method: .keyRemap,
                    nativeKeys: KeyCombo(from: "cmd+a")!
                ),
                Adapter.Mapping(
                    canonicalID: "find_in_page",
                    method: .passthrough
                ),
            ]
        )

        let selectAll = adapter.mappings.first { $0.canonicalID == "select_all" }
        XCTAssertNotNil(selectAll)
        XCTAssertEqual(selectAll?.method, .keyRemap)

        let find = adapter.mappings.first { $0.canonicalID == "find_in_page" }
        XCTAssertNotNil(find)
        XCTAssertEqual(find?.method, .passthrough)
    }

    // MARK: - IntentMatcher

    func testIntentMatcherFindsExactAlias() {
        let matcher = IntentMatcher()
        let item = MenuIntrospector.DiscoveredMenuItem(
            title: "Select All",
            menuPath: ["Edit", "Select All"],
            keyCombo: KeyCombo(from: "cmd+a")
        )

        let canonical = CanonicalShortcut.defaults.first { $0.id == "select_all" }!
        let result = matcher.bestMatch(for: canonical, among: [item])
        XCTAssertNotNil(result, "IntentMatcher should match 'Select All'")
        XCTAssertEqual(result?.title, "Select All")
    }

    func testIntentMatcherRejectsGarbage() {
        let matcher = IntentMatcher()
        let item = MenuIntrospector.DiscoveredMenuItem(
            title: "Frobulate the Widgets",
            menuPath: ["Special", "Frobulate the Widgets"],
            keyCombo: nil
        )

        // Try matching against a canonical that has no relation.
        let canonical = CanonicalShortcut.defaults.first { $0.id == "focus_url_bar" }!
        let result = matcher.bestMatch(for: canonical, among: [item])
        XCTAssertNil(result, "IntentMatcher should not match unrelated menu items")
    }
}
