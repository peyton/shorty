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
    public struct TraversalLimits: Equatable {
        public let maxDepth: Int
        public let maxItems: Int
        public let timeout: TimeInterval

        public init(
            maxDepth: Int = 8,
            maxItems: Int = 1_000,
            timeout: TimeInterval = 1.5
        ) {
            self.maxDepth = maxDepth
            self.maxItems = maxItems
            self.timeout = timeout
        }
    }

    /// A single discovered menu item with its keyboard shortcut.
    public struct DiscoveredMenuItem: Equatable {
        public let title: String
        public let menuPath: [String]  // e.g. ["File", "New Tab"]
        public let keyCombo: KeyCombo?
    }

    // MARK: - Public API

    /// Read all menu items (with shortcuts) from the given application.
    public func discoverMenuItems(
        pid: pid_t,
        limits: TraversalLimits = TraversalLimits()
    ) -> [DiscoveredMenuItem] {
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
        var state = TraversalState(limits: limits)
        walkMenu(element: menuBar, path: [], results: &results, state: &state)
        return results
    }

    @discardableResult
    public static func invokeMenuItem(
        pid: pid_t,
        title: String,
        menuPath: [String]? = nil,
        limits: TraversalLimits = TraversalLimits()
    ) -> Bool {
        let introspector = MenuIntrospector()
        return introspector.invokeMenuItem(
            pid: pid,
            title: title,
            menuPath: menuPath,
            limits: limits
        )
    }

    @discardableResult
    public func invokeMenuItem(
        pid: pid_t,
        title: String,
        menuPath: [String]? = nil,
        limits: TraversalLimits = TraversalLimits()
    ) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app,
            kAXMenuBarAttribute as CFString,
            &menuBarRef
        ) == .success,
        let menuBarRef
        else { return false }

        let menuBar = unsafeBitCast(menuBarRef, to: AXUIElement.self)
        var state = TraversalState(limits: limits)
        guard let item = findMenuItem(
            in: menuBar,
            title: title,
            menuPath: normalizedPath(menuPath, fallbackTitle: title),
            currentPath: [],
            state: &state
        ) else {
            return false
        }

        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
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
                            method: .passthrough,
                            matchReason: match.reason.displayString
                        ))
                    } else {
                        mappings.append(Adapter.Mapping(
                            canonicalID: canonical.id,
                            method: .keyRemap,
                            nativeKeys: nativeCombo,
                            matchReason: match.reason.displayString
                        ))
                    }
                } else {
                    // No keyboard shortcut — invoke via menu AX.
                    mappings.append(Adapter.Mapping(
                        canonicalID: canonical.id,
                        method: .menuInvoke,
                        menuTitle: match.item.title,
                        menuPath: match.item.menuPath,
                        matchReason: match.reason.displayString
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
        results: inout [DiscoveredMenuItem],
        state: inout TraversalState
    ) {
        guard state.canVisit(depth: path.count) else { return }

        // Get children of this element
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenRef
        ) == .success,
        let children = childrenRef as? [AXUIElement]
        else { return }

        for child in children {
            guard state.recordVisit(depth: path.count) else { return }
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
            walkMenu(
                element: child,
                path: currentPath,
                results: &results,
                state: &state
            )
        }
    }

    private func findMenuItem(
        in element: AXUIElement,
        title: String,
        menuPath: [String],
        currentPath: [String],
        state: inout TraversalState
    ) -> AXUIElement? {
        guard state.recordVisit(depth: currentPath.count) else { return nil }

        let elementTitle = axString(element, kAXTitleAttribute) ?? ""
        let role = axString(element, kAXRoleAttribute) ?? ""
        let nextPath = elementTitle.isEmpty ? currentPath : currentPath + [elementTitle]
        if role == "AXMenuItem",
           !elementTitle.isEmpty,
           pathMatches(nextPath, requestedPath: menuPath, fallbackTitle: title) {
            return element
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success,
        let children = childrenRef as? [AXUIElement]
        else { return nil }

        for child in children {
            if let item = findMenuItem(
                in: child,
                title: title,
                menuPath: menuPath,
                currentPath: nextPath,
                state: &state
            ) {
                return item
            }
        }
        return nil
    }

    private func normalizedPath(
        _ menuPath: [String]?,
        fallbackTitle: String
    ) -> [String] {
        let path = (menuPath ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return path.isEmpty ? [fallbackTitle] : path
    }

    private func pathMatches(
        _ actualPath: [String],
        requestedPath: [String],
        fallbackTitle: String
    ) -> Bool {
        guard !requestedPath.isEmpty else {
            return actualPath.last == fallbackTitle
        }
        if actualPath == requestedPath {
            return true
        }
        guard actualPath.count >= requestedPath.count else {
            return false
        }
        return Array(actualPath.suffix(requestedPath.count)) == requestedPath
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

private struct TraversalState {
    let limits: MenuIntrospector.TraversalLimits
    let startedAt = Date()
    let deadline: Date
    var visited = 0

    init(limits: MenuIntrospector.TraversalLimits) {
        self.limits = limits
        self.deadline = startedAt.addingTimeInterval(limits.timeout)
    }

    mutating func canVisit(depth: Int) -> Bool {
        guard depth <= limits.maxDepth else { return false }
        guard visited < limits.maxItems else { return false }
        return Date() <= deadline
    }

    mutating func recordVisit(depth: Int) -> Bool {
        guard canVisit(depth: depth) else { return false }
        visited += 1
        return true
    }
}
