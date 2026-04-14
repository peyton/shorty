import Foundation

/// Loads, caches, and queries per-app keyboard adapters.
///
/// The registry searches for adapters in this priority order:
/// 1. User-created adapters (~/Library/Application Support/Shorty/Adapters/)
/// 2. Auto-generated adapters from menu introspection (Phase 2)
/// 3. Built-in adapters bundled with the app
///
/// When no adapter exists for an app, the engine passes keystrokes through
/// unmodified — Shorty is strictly opt-in per app.
public final class AdapterRegistry: ObservableObject {

    /// All loaded adapters, keyed by app identifier.
    @Published public private(set) var adapters: [String: Adapter] = [:]

    /// Loaded adapters as a stable collection for UI lists.
    public var allAdapters: [Adapter] {
        Array(adapters.values)
    }

    /// Canonical shortcuts the user has configured.
    @Published public private(set) var canonicalShortcuts: [CanonicalShortcut] = CanonicalShortcut.defaults

    /// Quick lookup: canonical KeyCombo → canonical shortcut ID.
    /// Rebuilt whenever canonical shortcuts change.
    private(set) var comboToCanonicalID: [KeyCombo: String] = [:]

    private let userAdapterDirectory: URL
    private let autoAdapterDirectory: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let shortyDir = appSupport.appendingPathComponent("Shorty", isDirectory: true)
        self.userAdapterDirectory = shortyDir.appendingPathComponent("Adapters", isDirectory: true)
        self.autoAdapterDirectory = shortyDir.appendingPathComponent("AutoAdapters", isDirectory: true)

        // Ensure directories exist
        try? FileManager.default.createDirectory(at: userAdapterDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: autoAdapterDirectory, withIntermediateDirectories: true)

        rebuildComboIndex()
        loadAllAdapters()
    }

    // MARK: - Lookup

    /// Check whether an adapter exists for a given app identifier.
    public func hasAdapter(for appID: String) -> Bool {
        adapters[appID] != nil
    }

    /// Find the adapter for a given app identifier.
    public func adapter(for appID: String) -> Adapter? {
        adapters[appID]
    }

    /// Find the adapter currently active for an effective app identifier.
    public func activeAdapter(for appID: String) -> Adapter? {
        adapter(for: appID)
    }

    /// Resolve a key event to a native action.
    /// Returns the native KeyCombo to send, or nil if no remapping is needed.
    public func resolve(combo: KeyCombo, forApp appID: String) -> ResolvedAction? {
        guard let canonicalID = comboToCanonicalID[combo] else { return nil }
        guard let adapter = adapters[appID] else { return nil }
        guard let mapping = adapter.mappings.first(where: { $0.canonicalID == canonicalID }) else { return nil }

        switch mapping.method {
        case .keyRemap:
            guard let nativeKeys = mapping.nativeKeys else { return nil }
            return .remap(nativeKeys)
        case .menuInvoke:
            guard let title = mapping.menuTitle else { return nil }
            return .invokeMenu(title)
        case .axAction:
            guard let action = mapping.axAction else { return nil }
            return .performAXAction(action)
        case .passthrough:
            return .passthrough
        }
    }

    /// What the engine should do after resolving a canonical shortcut.
    public enum ResolvedAction {
        /// Rewrite the event to this key combo.
        case remap(KeyCombo)
        /// Suppress the event and invoke a menu item by title (Phase 2).
        case invokeMenu(String)
        /// Suppress the event and perform an AX action (Phase 2).
        case performAXAction(String)
        /// Let the event pass through unmodified.
        case passthrough
    }

    // MARK: - Adapter management

    /// Save an auto-generated adapter (from menu introspection).
    public func saveAutoAdapter(_ adapter: Adapter) throws {
        let url = autoAdapterDirectory
            .appendingPathComponent(adapter.appIdentifier.replacingOccurrences(of: ":", with: "_"))
            .appendingPathExtension("json")
        let data = try JSONEncoder.pretty.encode(adapter)
        try data.write(to: url)
        adapters[adapter.appIdentifier] = adapter
    }

    /// Save a user-created adapter.
    public func saveUserAdapter(_ adapter: Adapter) throws {
        let url = userAdapterDirectory
            .appendingPathComponent(adapter.appIdentifier.replacingOccurrences(of: ":", with: "_"))
            .appendingPathExtension("json")
        let data = try JSONEncoder.pretty.encode(adapter)
        try data.write(to: url)
        adapters[adapter.appIdentifier] = adapter
    }

    /// Reload all adapters from disk (called after auto-generation saves a new one).
    public func reloadAdapters() {
        adapters.removeAll()
        loadAllAdapters()
    }

    // MARK: - Loading

    private func loadAllAdapters() {
        // 1. Load built-in adapters from bundle
        loadBuiltinAdapters()

        // 2. Load auto-generated adapters (may override built-in)
        loadAdapters(from: autoAdapterDirectory)

        // 3. Load user adapters (highest priority, override everything)
        loadAdapters(from: userAdapterDirectory)
    }

    private func loadBuiltinAdapters() {
        guard let resourceURL = Self.bundledResourcesURL else {
            print("[AdapterRegistry] No bundled Resources directory found")
            // Fall back to built-in adapters defined in code
            loadHardcodedAdapters()
            return
        }

        let adaptersDir = resourceURL.appendingPathComponent("Adapters", isDirectory: true)
        loadAdapters(from: adaptersDir)

        // Also load hardcoded adapters for anything not covered by JSON files
        loadHardcodedAdapters()
    }

    private static var bundledResourcesURL: URL? {
        let fileManager = FileManager.default
        let bundle = Bundle(for: AdapterRegistry.self)
        let candidates = [
            bundle.url(forResource: "Resources", withExtension: nil),
            bundle.resourceURL?.appendingPathComponent("Resources", isDirectory: true),
            Bundle.main.url(forResource: "Resources", withExtension: nil),
            Bundle.main.resourceURL?.appendingPathComponent("Resources", isDirectory: true)
        ].compactMap { $0 }

        return candidates.first { fileManager.fileExists(atPath: $0.path) }
    }

    private func loadAdapters(from directory: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for fileURL in contents where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let adapter = try? JSONDecoder().decode(Adapter.self, from: data) else {
                print("[AdapterRegistry] Failed to load adapter: \(fileURL.lastPathComponent)")
                continue
            }
            adapters[adapter.appIdentifier] = adapter
        }
    }

    private func rebuildComboIndex() {
        comboToCanonicalID = [:]
        for shortcut in canonicalShortcuts {
            comboToCanonicalID[shortcut.defaultKeys] = shortcut.id
        }
    }

    // MARK: - Hardcoded adapters for the top 20 apps

    private func loadHardcodedAdapters() {
        let builtins = Self.builtinAdapters
        // Only insert if not already loaded from JSON.
        for adapter in builtins where adapters[adapter.appIdentifier] == nil {
            adapters[adapter.appIdentifier] = adapter
        }
    }

    static let builtinAdapters: [Adapter] = [
        // VS Code: Cmd+L → Cmd+G (go to line), but for URL bar intent we map to Cmd+P (quick open)
        Adapter(
            appIdentifier: "com.microsoft.VSCode",
            appName: "Visual Studio Code",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x23, modifiers: .command)), // Cmd+P (quick open)
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x23, modifiers: [.command, .shift])), // Cmd+Shift+P
                .init(canonicalID: "find_and_replace", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x04, modifiers: [.command, .option])), // Cmd+Option+F
                .init(canonicalID: "newline_in_field", method: .passthrough) // Enter is already newline in editor
            ]
        ),

        // Slack: Shift+Enter normally sends; we want it to be newline
        Adapter(
            appIdentifier: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            mappings: [
                .init(canonicalID: "newline_in_field", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x24, modifiers: [.option])), // Option+Enter = newline in Slack
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command)), // Cmd+F
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x28, modifiers: .command)) // Cmd+K
            ]
        ),

        // Discord
        Adapter(
            appIdentifier: "com.hnc.Discord",
            appName: "Discord",
            mappings: [
                .init(canonicalID: "newline_in_field", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x24, modifiers: [.shift])), // Shift+Enter (same)
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x28, modifiers: .command)) // Cmd+K
            ]
        ),

        // Finder
        Adapter(
            appIdentifier: "com.apple.finder",
            appName: "Finder",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x25, modifiers: [.command, .shift])), // Cmd+Shift+G (Go to Folder)
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command)), // Cmd+F
                .init(canonicalID: "new_tab", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x11, modifiers: .command)) // Cmd+T
            ]
        ),

        // Terminal
        Adapter(
            appIdentifier: "com.apple.Terminal",
            appName: "Terminal",
            mappings: [
                .init(canonicalID: "new_tab", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x11, modifiers: .command)), // Cmd+T
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command)), // Cmd+F
                .init(canonicalID: "newline_in_field", method: .passthrough)
            ]
        ),

        // iTerm2
        Adapter(
            appIdentifier: "com.googlecode.iterm2",
            appName: "iTerm2",
            mappings: [
                .init(canonicalID: "new_tab", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x11, modifiers: .command)), // Cmd+T
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command)), // Cmd+F
                .init(canonicalID: "newline_in_field", method: .passthrough)
            ]
        ),

        // Xcode
        Adapter(
            appIdentifier: "com.apple.dt.Xcode",
            appName: "Xcode",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x1F, modifiers: [.command, .shift])), // Cmd+Shift+O (Open Quickly)
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x1F, modifiers: [.command, .shift])), // Cmd+Shift+O
                .init(canonicalID: "find_and_replace", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: [.command, .option])), // Cmd+Option+F
                .init(canonicalID: "newline_in_field", method: .passthrough)
            ]
        ),

        // Notes
        Adapter(
            appIdentifier: "com.apple.Notes",
            appName: "Notes",
            mappings: [
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command)),
                .init(canonicalID: "newline_in_field", method: .passthrough) // Enter is already newline
            ]
        ),

        // Mail
        Adapter(
            appIdentifier: "com.apple.mail",
            appName: "Mail",
            mappings: [
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command)),
                .init(canonicalID: "submit_field", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x24, modifiers: [.command, .shift])) // Cmd+Shift+Enter = send
            ]
        ),

        // Messages
        Adapter(
            appIdentifier: "com.apple.MobileSMS",
            appName: "Messages",
            mappings: [
                .init(canonicalID: "newline_in_field", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x24, modifiers: [.option])) // Option+Enter for newline
            ]
        ),

        // Notion (desktop)
        Adapter(
            appIdentifier: "notion.id",
            appName: "Notion",
            mappings: [
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x23, modifiers: .command)), // Cmd+P
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command)),
                .init(canonicalID: "newline_in_field", method: .passthrough) // Enter is newline in Notion blocks
            ]
        ),

        // Obsidian
        Adapter(
            appIdentifier: "md.obsidian",
            appName: "Obsidian",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x1F, modifiers: .command)), // Cmd+O (quick switcher)
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x23, modifiers: .command)), // Cmd+P
                .init(canonicalID: "newline_in_field", method: .passthrough)
            ]
        ),

        // Telegram
        Adapter(
            appIdentifier: "ru.keepcoder.Telegram",
            appName: "Telegram",
            mappings: [
                .init(canonicalID: "newline_in_field", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x24, modifiers: [.shift])) // Shift+Enter (native)
            ]
        ),

        // 1Password
        Adapter(
            appIdentifier: "com.1password.1password",
            appName: "1Password",
            mappings: [
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command))
            ]
        ),

        // Spotify
        Adapter(
            appIdentifier: "com.spotify.client",
            appName: "Spotify",
            mappings: [
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x25, modifiers: .command)), // Cmd+L (search in Spotify)
                .init(canonicalID: "toggle_play_pause", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x31, modifiers: [])) // Space
            ]
        ),

        // Safari — most canonical shortcuts already match Safari's native ones
        Adapter(
            appIdentifier: "com.apple.Safari",
            appName: "Safari",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough), // Cmd+L is native
                .init(canonicalID: "find_in_page", method: .passthrough),  // Cmd+F is native
                .init(canonicalID: "new_tab", method: .passthrough),       // Cmd+T is native
                .init(canonicalID: "close_tab", method: .passthrough)     // Cmd+W is native
            ]
        ),

        // Chrome
        Adapter(
            appIdentifier: "com.google.Chrome",
            appName: "Google Chrome",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough), // Cmd+L is native
                .init(canonicalID: "find_in_page", method: .passthrough),
                .init(canonicalID: "new_tab", method: .passthrough),
                .init(canonicalID: "close_tab", method: .passthrough),
                .init(canonicalID: "reopen_tab", method: .passthrough)
            ]
        ),

        // Firefox
        Adapter(
            appIdentifier: "org.mozilla.firefox",
            appName: "Firefox",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough),
                .init(canonicalID: "find_in_page", method: .passthrough),
                .init(canonicalID: "new_tab", method: .passthrough),
                .init(canonicalID: "close_tab", method: .passthrough)
            ]
        ),

        // Arc
        Adapter(
            appIdentifier: "company.thebrowser.Browser",
            appName: "Arc",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x25, modifiers: .command)), // Cmd+L (same, but Arc may differ)
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x11, modifiers: .command)), // Cmd+T opens command bar in Arc
                .init(canonicalID: "new_tab", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x11, modifiers: .command)) // Cmd+T
            ]
        ),

        // Notion web
        Adapter(
            appIdentifier: "web:notion.so",
            appName: "Notion Web",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough),
                .init(canonicalID: "find_in_page", method: .passthrough),
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x23, modifiers: .command)), // Cmd+P
                .init(canonicalID: "newline_in_field", method: .passthrough)
            ]
        ),

        // Slack web
        Adapter(
            appIdentifier: "web:slack.com",
            appName: "Slack Web",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough),
                .init(canonicalID: "find_in_page", method: .passthrough),
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x28, modifiers: .command)), // Cmd+K
                .init(canonicalID: "newline_in_field", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x24, modifiers: [.option]))
            ]
        ),

        // Gmail web
        Adapter(
            appIdentifier: "web:mail.google.com",
            appName: "Gmail Web",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough),
                .init(canonicalID: "find_in_page", method: .passthrough),
                .init(canonicalID: "submit_field", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x24, modifiers: .command)), // Cmd+Return
                .init(canonicalID: "newline_in_field", method: .passthrough)
            ]
        ),

        // Google Docs web
        Adapter(
            appIdentifier: "web:docs.google.com",
            appName: "Google Docs Web",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough),
                .init(canonicalID: "find_in_page", method: .passthrough),
                .init(canonicalID: "find_and_replace", method: .passthrough),
                .init(canonicalID: "newline_in_field", method: .passthrough)
            ]
        ),

        // Figma web
        Adapter(
            appIdentifier: "web:figma.com",
            appName: "Figma Web",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough),
                .init(canonicalID: "find_in_page", method: .passthrough),
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x2C, modifiers: .command)) // Cmd+/
            ]
        ),

        // Linear web
        Adapter(
            appIdentifier: "web:linear.app",
            appName: "Linear Web",
            mappings: [
                .init(canonicalID: "focus_url_bar", method: .passthrough),
                .init(canonicalID: "find_in_page", method: .passthrough),
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x28, modifiers: .command)) // Cmd+K
            ]
        ),

        // Linear
        Adapter(
            appIdentifier: "com.linear",
            appName: "Linear",
            mappings: [
                .init(canonicalID: "command_palette", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x28, modifiers: .command)), // Cmd+K
                .init(canonicalID: "find_in_page", method: .keyRemap,
                      nativeKeys: KeyCombo(keyCode: 0x03, modifiers: .command))
            ]
        )
    ]
}

// MARK: - JSON encoder helper

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
