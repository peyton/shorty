import AppKit
import ApplicationServices

/// Phase 2: Reads an application's menu bar via the Accessibility API
/// and generates an Adapter by matching discovered menu shortcuts to
/// canonical shortcut intents.
///
/// ## AX menu model
///
/// ```
/// AXApplication
///   └─ AXMenuBar
///       └─ AXMenuBarItem ("File")
///           └─ AXMenu
///               └─ AXMenuItem ("New Tab")
///                   ├─ AXMenuItemCmdChar: "T"
///                   ├─ AXMenuItemCmdModifiers: 0  (⌘ only)
///                   └─ AXTitle: "New Tab"
/// ```
///
/// `AXMenuItemCmdModifiers` is a bitmask of *excluded* modifiers:
///   - bit 0 clear = ⌘ present (always present for menu shortcuts)
///   - bit 1 set   = ⇧ present
///   - bit 2 set   = ⌥ present
///   - bit 3 set   = ⌃ present
///
/// Yeah, it's confusing. Apple's docs are… sparse.
public final class MenuIntrospector {

    /// A single discovered menu item with its keyboard shortcut.
    public struct DiscoveredMenuItem: Equatable {
        public let title: String
        public let menuPath: [String]  // e.g. ["File", "New Tab"]
        public let keyCombo: KeyCombo?
    }

    // MARK: - Public API

    /// Read all menu items (with shortcuts) from the given application.
    public func discoverMenuItems(pid: pid_t) -> [DiscoveredMenuItem] {
        let app = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXMenuBarAttribute as CFString, &menuBarRef
        ) == .success else {
            return []
        }

        guard let menuBarRef else {
            return []
        }
        let menuBar = unsafeBitCast(menuBarRef, to: AXUIElement.self)

        var results: [DiscoveredMenuItem] = []
        walkMenu(element: menuBar, path: [], results: &results)
        return results
    }

    /// Generate an Adapter for the given app by matching discovered
    /// menu items to canonical shortcuts.
    public func generateAdapter(
        bundleID: String,
        appName: String,
        pid: pid_t,
        canonicals: [CanonicalShortcut]
    ) -> Adapter? {
        let items = discoverMenuItems(pid: pid)
        guard !items.isEmpty else { return nil }

        let matcher = IntentMatcher()
        var mappings: [Adapter.Mapping] = []

        for canonical in canonicals {
            // Try to find a matching menu item for this intent.
            if let match = matcher.bestMatch(
                for: canonical,
                among: items
            ) {
                if let nativeCombo = match.item.keyCombo {
                    // The menu item has a keyboard shortcut — use keyRemap.
                    if nativeCombo == canonical.defaultKeys {
                        // Same keys — passthrough.
                        mappings.append(Adapter.Mapping(
                            canonicalID: canonical.id,
                            method: .passthrough
                        ))
                    } else {
                        mappings.append(Adapter.Mapping(
                            canonicalID: canonical.id,
                            method: .keyRemap,
                            nativeKeys: nativeCombo
                        ))
                    }
                } else {
                    // No keyboard shortcut — invoke via menu AX.
                    mappings.append(Adapter.Mapping(
                        canonicalID: canonical.id,
                        method: .menuInvoke,
                        menuTitle: match.item.title
                    ))
                }
            }
        }

        guard !mappings.isEmpty else { return nil }

        return Adapter(
            appIdentifier: bundleID,
            appName: appName,
            source: .menuIntrospection,
            mappings: mappings
        )
    }

    // MARK: - Recursive menu walker

    private func walkMenu(
        element: AXUIElement,
        path: [String],
        results: inout [DiscoveredMenuItem]
    ) {
        // Get children of this element
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        ) == .success,
        let children = childrenRef as? [AXUIElement]
        else { return }

        for child in children {
            let title = axString(child, kAXTitleAttribute) ?? ""
            let role = axString(child, kAXRoleAttribute) ?? ""
            let currentPath = title.isEmpty ? path : path + [title]

            // If this is a menu item with a command key, record it.
            if role == "AXMenuItem" && !title.isEmpty {
                let combo = extractKeyCombo(from: child)
                results.append(DiscoveredMenuItem(
                    title: title,
                    menuPath: currentPath,
                    keyCombo: combo
                ))
            }

            // Recurse into submenus
            walkMenu(element: child, path: currentPath, results: &results)
        }
    }

    // MARK: - Key combo extraction from AX attributes

    private func extractKeyCombo(from item: AXUIElement) -> KeyCombo? {
        // AXMenuItemCmdChar — the character (e.g. "T", "W", ",")
        guard let cmdChar = axString(item, "AXMenuItemCmdChar"),
              !cmdChar.isEmpty
        else { return nil }

        // AXMenuItemCmdModifiers — integer bitmask
        let modMask = axInt(item, "AXMenuItemCmdModifiers") ?? 0

        // Convert AX modifier bitmask to our Modifiers.
        // AX conventions (yes, this is bizarre):
        //   0 = ⌘ only
        //   bit 1 (value 2) = ⇧
        //   bit 2 (value 4) = ⌥
        //   bit 3 (value 8) = ⌃
        // ⌘ is *always* implied unless bit 0 (value 1) is set,
        // which means "no ⌘" (rare).
        var mods: KeyCombo.Modifiers = []
        if (modMask & 1) == 0 { mods.insert(.command) }
        if (modMask & 2) != 0 { mods.insert(.shift) }
        if (modMask & 4) != 0 { mods.insert(.option) }
        if (modMask & 8) != 0 { mods.insert(.control) }

        // Convert the character to a keycode.
        let char = cmdChar.lowercased()
        guard let keyCode = KeyCodeMap.keyCode(for: char) else { return nil }

        return KeyCombo(keyCode: keyCode, modifiers: mods)
    }

    // MARK: - AX helpers

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &ref
        ) == .success else { return nil }
        return ref as? String
    }

    private func axInt(_ element: AXUIElement, _ attribute: String) -> Int? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, attribute as CFString, &ref
        ) == .success else { return nil }
        if let num = ref as? NSNumber {
            return num.intValue
        }
        return nil
    }
}
