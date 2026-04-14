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
        let parsedCombo = KeyCombo(from: "cmd+c")
        let builtCombo = KeyCombo(keyCode: 8, modifiers: .command)
        XCTAssertEqual(parsedCombo, builtCombo)
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
                )
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
            keyCombo: nil
        )

        let canonical = CanonicalShortcut.defaults.first { $0.id == "select_all" }!
        let result = matcher.bestMatch(for: canonical, among: [item])
        XCTAssertNotNil(result, "IntentMatcher should match 'Select All'")
        XCTAssertEqual(result?.item.title, "Select All")
        XCTAssertEqual(result?.reason, .exactAlias)
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

    func testIntentMatcherFindsExactKeyCombo() {
        let matcher = IntentMatcher()
        let canonical = CanonicalShortcut.defaults.first { $0.id == "focus_url_bar" }!
        let item = MenuIntrospector.DiscoveredMenuItem(
            title: "Open Something Else",
            menuPath: ["File", "Open Something Else"],
            keyCombo: canonical.defaultKeys
        )

        let result = matcher.bestMatch(for: canonical, among: [item])
        XCTAssertEqual(result?.item.title, "Open Something Else")
        XCTAssertEqual(result?.reason, .exactKeyCombo)
        XCTAssertGreaterThanOrEqual(result?.score ?? 0, IntentMatcher.minimumScore)
    }

    func testIntentMatcherRejectsAmbiguousMatches() {
        let matcher = IntentMatcher()
        let canonical = CanonicalShortcut.defaults.first { $0.id == "select_all" }!
        let items = [
            MenuIntrospector.DiscoveredMenuItem(
                title: "Select All",
                menuPath: ["Edit", "Select All"],
                keyCombo: nil
            ),
            MenuIntrospector.DiscoveredMenuItem(
                title: "Select All Items",
                menuPath: ["Edit", "Select All Items"],
                keyCombo: nil
            )
        ]

        let result = matcher.bestMatch(for: canonical, among: items)
        XCTAssertNil(result, "IntentMatcher should reject close competing matches")
    }

    // MARK: - Domain normalization

    func testDomainNormalizerKnownDomains() {
        XCTAssertEqual(
            DomainNormalizer.adapterIdentifier(for: "workspace.slack.com"),
            "web:slack.com"
        )
        XCTAssertEqual(
            DomainNormalizer.adapterIdentifier(for: "www.figma.com"),
            "web:figma.com"
        )
        XCTAssertEqual(
            DomainNormalizer.adapterIdentifier(for: "mail.google.com"),
            "web:mail.google.com"
        )
        XCTAssertEqual(
            DomainNormalizer.adapterIdentifier(for: "docs.google.com"),
            "web:docs.google.com"
        )
    }

    func testDomainNormalizerUnknownDomain() {
        XCTAssertEqual(
            DomainNormalizer.adapterIdentifier(for: "Example.COM."),
            "web:example.com"
        )
    }

    // MARK: - Browser bridge

    func testBrowserBridgeDecodesDomainMessage() {
        let payload = Data(#"{"type":"domain_changed","domain":"workspace.slack.com"}"#.utf8)
        XCTAssertEqual(
            BrowserBridge.decodeMessagePayload(payload),
            .domainChanged("slack.com")
        )
    }

    func testBrowserBridgeRejectsInvalidMessage() {
        let payload = Data(#"{"type":"other","domain":"slack.com"}"#.utf8)
        XCTAssertNil(BrowserBridge.decodeMessagePayload(payload))
    }

    func testBrowserBridgeRejectsOversizedLength() {
        let oversized = BrowserBridge.maxMessageLength + 1
        let bytes = [
            UInt8(oversized & 0xFF),
            UInt8((oversized >> 8) & 0xFF),
            UInt8((oversized >> 16) & 0xFF),
            UInt8((oversized >> 24) & 0xFF)
        ]
        XCTAssertNil(BrowserBridge.messageLength(from: bytes))
    }

    func testBrowserBridgeAcceptsValidLength() {
        XCTAssertEqual(
            BrowserBridge.messageLength(from: [12, 0, 0, 0]),
            UInt32(12)
        )
    }

    // MARK: - Web adapters

    func testRegistryIncludesWebAdapters() {
        let ids = Set(AdapterRegistry.builtinAdapters.map(\.appIdentifier))
        XCTAssertTrue(ids.contains("web:notion.so"))
        XCTAssertTrue(ids.contains("web:slack.com"))
        XCTAssertTrue(ids.contains("web:mail.google.com"))
        XCTAssertTrue(ids.contains("web:docs.google.com"))
        XCTAssertTrue(ids.contains("web:figma.com"))
        XCTAssertTrue(ids.contains("web:linear.app"))
    }
}
