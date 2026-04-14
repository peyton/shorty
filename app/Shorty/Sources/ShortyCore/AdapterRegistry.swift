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
    public static let maxAdapterFileSize = 256 * 1024

    /// All loaded adapters, keyed by app identifier.
    @Published public private(set) var adapters: [String: Adapter] = [:]

    /// Non-fatal validation messages for adapters skipped during loading.
    @Published public private(set) var validationMessages: [String] = []

    /// Loaded adapters as a stable collection for UI lists.
    public var allAdapters: [Adapter] {
        Array(adapters.values)
    }

    /// Canonical shortcuts the user has configured.
    @Published public private(set) var canonicalShortcuts: [CanonicalShortcut] = CanonicalShortcut.defaults

    /// Quick lookup: canonical KeyCombo → canonical shortcut ID.
    /// Rebuilt whenever canonical shortcuts change.
    private(set) var comboToCanonicalID: [KeyCombo: String] = [:]

    /// Fast path used from the event tap: app ID -> canonical ID -> action.
    private var actionIndex: [String: [String: ResolvedAction]] = [:]

    private let fileManager: FileManager
    private let userAdapterDirectory: URL
    private let autoAdapterDirectory: URL

    public init(
        fileManager: FileManager = .default,
        appSupportDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        let appSupport = appSupportDirectory
            ?? fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let shortyDir = appSupport.appendingPathComponent("Shorty", isDirectory: true)
        self.userAdapterDirectory = shortyDir.appendingPathComponent("Adapters", isDirectory: true)
        self.autoAdapterDirectory = shortyDir.appendingPathComponent("AutoAdapters", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: userAdapterDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: autoAdapterDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            ShortyLog.adapterRegistry.error("Failed to create adapter directories: \(error.localizedDescription)")
        }

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
        return actionIndex[appID]?[canonicalID]
    }

    public func mappingCount(for appID: String) -> Int {
        adapters[appID]?.mappings.count ?? 0
    }

    /// What the engine should do after resolving a canonical shortcut.
    public enum ResolvedAction: Equatable {
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

    public static func validate(
        adapter: Adapter,
        canonicals: [CanonicalShortcut] = CanonicalShortcut.defaults
    ) throws {
        try validateAdapterMetadata(adapter)
        try validateMappings(adapter.mappings, canonicals: canonicals)
    }

    private static func validateAdapterMetadata(_ adapter: Adapter) throws {
        let appIdentifier = adapter.appIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !appIdentifier.isEmpty else {
            throw AdapterValidationError.emptyAppIdentifier
        }
        guard appIdentifier.count <= 200,
              !appIdentifier.contains("/"),
              !appIdentifier.contains("\0")
        else {
            throw AdapterValidationError.invalidAppIdentifier(adapter.appIdentifier)
        }

        guard !adapter.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AdapterValidationError.emptyAppName
        }
        guard !adapter.mappings.isEmpty else {
            throw AdapterValidationError.noMappings(adapter.appIdentifier)
        }
        guard adapter.mappings.count <= 100 else {
            throw AdapterValidationError.tooManyMappings(adapter.appIdentifier)
        }
    }

    private static func validateMappings(
        _ mappings: [Adapter.Mapping],
        canonicals: [CanonicalShortcut]
    ) throws {
        let canonicalIDs = Set(canonicals.map(\.id))
        var seenCanonicalIDs = Set<String>()

        for mapping in mappings {
            try validateMapping(
                mapping,
                canonicalIDs: canonicalIDs,
                seenCanonicalIDs: &seenCanonicalIDs
            )
        }
    }

    private static func validateMapping(
        _ mapping: Adapter.Mapping,
        canonicalIDs: Set<String>,
        seenCanonicalIDs: inout Set<String>
    ) throws {
        guard canonicalIDs.contains(mapping.canonicalID) else {
            throw AdapterValidationError.unknownCanonicalID(mapping.canonicalID)
        }
        guard seenCanonicalIDs.insert(mapping.canonicalID).inserted else {
            throw AdapterValidationError.duplicateCanonicalID(mapping.canonicalID)
        }
        try validateContext(mapping.context, canonicalID: mapping.canonicalID)

        switch mapping.method {
        case .keyRemap:
            try validateKeyRemap(mapping)
        case .menuInvoke:
            try validateMenuInvoke(mapping)
        case .axAction:
            try validateAXAction(mapping)
        case .passthrough:
            try validatePassthrough(mapping)
        }
    }

    private static func validateContext(
        _ context: String?,
        canonicalID: String
    ) throws {
        guard let context else { return }
        if context.isEmpty || context.count > 100 || context.contains("\0") {
            throw AdapterValidationError.invalidContext(canonicalID)
        }
    }

    private static func validateKeyRemap(_ mapping: Adapter.Mapping) throws {
        guard mapping.nativeKeys != nil else {
            throw AdapterValidationError.missingNativeKeys(mapping.canonicalID)
        }
        guard mapping.menuTitle == nil else {
            throw AdapterValidationError.unexpectedMenuTitle(mapping.canonicalID)
        }
        guard mapping.axAction == nil else {
            throw AdapterValidationError.unexpectedAXAction(mapping.canonicalID)
        }
    }

    private static func validateMenuInvoke(_ mapping: Adapter.Mapping) throws {
        guard mapping.nativeKeys == nil else {
            throw AdapterValidationError.unexpectedNativeKeys(mapping.canonicalID)
        }
        guard let title = mapping.menuTitle?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !title.isEmpty, title.count <= 200 else {
            throw AdapterValidationError.missingMenuTitle(mapping.canonicalID)
        }
        guard mapping.axAction == nil else {
            throw AdapterValidationError.unexpectedAXAction(mapping.canonicalID)
        }
    }

    private static func validateAXAction(_ mapping: Adapter.Mapping) throws {
        guard mapping.nativeKeys == nil else {
            throw AdapterValidationError.unexpectedNativeKeys(mapping.canonicalID)
        }
        guard mapping.menuTitle == nil else {
            throw AdapterValidationError.unexpectedMenuTitle(mapping.canonicalID)
        }
        guard let action = mapping.axAction?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), action.hasPrefix("AX"), action.count <= 100 else {
            throw AdapterValidationError.missingAXAction(mapping.canonicalID)
        }
    }

    private static func validatePassthrough(_ mapping: Adapter.Mapping) throws {
        guard mapping.nativeKeys == nil else {
            throw AdapterValidationError.unexpectedNativeKeys(mapping.canonicalID)
        }
        guard mapping.menuTitle == nil else {
            throw AdapterValidationError.unexpectedMenuTitle(mapping.canonicalID)
        }
        guard mapping.axAction == nil else {
            throw AdapterValidationError.unexpectedAXAction(mapping.canonicalID)
        }
    }

    /// Save an auto-generated adapter (from menu introspection).
    public func saveAutoAdapter(_ adapter: Adapter) throws {
        try save(adapter, to: autoAdapterDirectory)
    }

    /// Save a user-created adapter.
    public func saveUserAdapter(_ adapter: Adapter) throws {
        try save(adapter, to: userAdapterDirectory)
    }

    private func save(_ adapter: Adapter, to directory: URL) throws {
        try Self.validate(adapter: adapter, canonicals: canonicalShortcuts)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory
            .appendingPathComponent(safeAdapterFilename(for: adapter.appIdentifier))
            .appendingPathExtension("json")
        let data = try JSONEncoder.pretty.encode(adapter)
        try data.write(to: url, options: .atomic)
        adapters[adapter.appIdentifier] = adapter
        rebuildActionIndex()
    }

    /// Reload all adapters from disk (called after auto-generation saves a new one).
    public func reloadAdapters() {
        adapters.removeAll()
        validationMessages.removeAll()
        loadAllAdapters()
    }

    public func applyShortcutProfile(_ profile: UserShortcutProfile) {
        canonicalShortcuts = profile.shortcuts
        rebuildComboIndex()
        rebuildActionIndex()
    }

    // MARK: - Loading

    private func loadAllAdapters() {
        // 1. Load built-in adapters from bundle
        loadBuiltinAdapters()

        // 2. Load auto-generated adapters (may override built-in)
        loadAdapters(from: autoAdapterDirectory)

        // 3. Load user adapters (highest priority, override everything)
        loadAdapters(from: userAdapterDirectory)

        rebuildActionIndex()
    }

    private func loadBuiltinAdapters() {
        guard let resourceURL = Self.bundledResourcesURL else {
            ShortyLog.adapterRegistry.debug("No bundled Resources directory found")
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
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return }

        for fileURL in contents where fileURL.pathExtension == "json" {
            do {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                let fileSize = values.fileSize ?? 0
                guard fileSize <= Self.maxAdapterFileSize else {
                    throw AdapterValidationError.fileTooLarge(fileSize)
                }

                let data = try Data(contentsOf: fileURL)
                let adapter = try JSONDecoder().decode(Adapter.self, from: data)
                try Self.validate(adapter: adapter, canonicals: canonicalShortcuts)
                adapters[adapter.appIdentifier] = adapter
            } catch {
                let message = "\(fileURL.lastPathComponent): \(error)"
                validationMessages.append(message)
                ShortyLog.adapterRegistry.warning("Skipped adapter \(message)")
                continue
            }
        }
    }

    private func rebuildComboIndex() {
        comboToCanonicalID = [:]
        for shortcut in canonicalShortcuts {
            comboToCanonicalID[shortcut.defaultKeys] = shortcut.id
        }
    }

    private func rebuildActionIndex() {
        var nextIndex: [String: [String: ResolvedAction]] = [:]
        for adapter in adapters.values {
            var mappingIndex: [String: ResolvedAction] = [:]
            for mapping in adapter.mappings {
                guard let action = resolvedAction(for: mapping) else { continue }
                mappingIndex[mapping.canonicalID] = action
            }
            nextIndex[adapter.appIdentifier] = mappingIndex
        }
        actionIndex = nextIndex
    }

    private func resolvedAction(for mapping: Adapter.Mapping) -> ResolvedAction? {
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

    private func safeAdapterFilename(for appIdentifier: String) -> String {
        appIdentifier
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Hardcoded adapters for the top 20 apps

    private func loadHardcodedAdapters() {
        let builtins = Self.builtinAdapters
        // Only insert if not already loaded from JSON.
        for adapter in builtins where adapters[adapter.appIdentifier] == nil {
            do {
                try Self.validate(adapter: adapter, canonicals: canonicalShortcuts)
                adapters[adapter.appIdentifier] = adapter
            } catch {
                let message = "\(adapter.appIdentifier): \(error)"
                validationMessages.append(message)
                ShortyLog.adapterRegistry.error("Invalid built-in adapter \(message)")
            }
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
