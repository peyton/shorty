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
    public static let maxAdapterFilesPerDirectory = 500

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
    private var mappingIndex: [String: [String: Adapter.Mapping]] = [:]
    private var sourceIndex: [String: Adapter.Source] = [:]
    private var shortcutProfile: UserShortcutProfile = .releaseDefault
    private var resolutionSnapshot = ResolutionSnapshot()
    private let stateLock = NSRecursiveLock()

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
        stateLock.lock()
        defer { stateLock.unlock() }
        return adapters[appID] != nil
    }

    /// Find the adapter for a given app identifier.
    public func adapter(for appID: String) -> Adapter? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return adapters[appID]
    }

    /// Find the adapter currently active for an effective app identifier.
    public func activeAdapter(for appID: String) -> Adapter? {
        adapter(for: appID)
    }

    /// Resolve a key event to a native action.
    /// Returns the native KeyCombo to send, or nil if no remapping is needed.
    public func resolve(combo: KeyCombo, forApp appID: String) -> ResolvedAction? {
        resolveShortcut(combo: combo, forApp: appID)?.action
    }

    public func resolveShortcut(
        combo: KeyCombo,
        forApp appID: String
    ) -> ResolvedShortcutAction? {
        let snapshot = currentResolutionSnapshot()
        guard snapshot.enabledAdapterIDs.contains(appID),
              let canonicalID = snapshot.comboToCanonicalID[combo],
              let action = snapshot.actionIndex[appID]?[canonicalID],
              let mapping = snapshot.mappingIndex[appID]?[canonicalID]
        else { return nil }

        return ResolvedShortcutAction(
            appIdentifier: appID,
            canonicalID: canonicalID,
            mapping: mapping,
            action: action,
            adapterSource: snapshot.sourceIndex[appID] ?? .builtin
        )
    }

    public func mappingCount(for appID: String) -> Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return adapters[appID]?.mappings.count ?? 0
    }

    public func availability(
        for appID: String?,
        displayName: String?
    ) -> ShortcutAvailability {
        guard let appID else {
            return ShortcutAvailability(
                state: .noActiveApp,
                appIdentifier: nil,
                appDisplayName: "Unknown"
            )
        }

        let snapshotProfile: UserShortcutProfile
        let adapter: Adapter?
        stateLock.lock()
        snapshotProfile = shortcutProfile
        adapter = adapters[appID]
        stateLock.unlock()

        guard let adapter else {
            return ShortcutAvailability(
                state: .noAdapter,
                appIdentifier: appID,
                appDisplayName: displayName ?? appID
            )
        }

        guard snapshotProfile.isAdapterEnabled(appID) else {
            return ShortcutAvailability(
                state: .paused,
                appIdentifier: appID,
                appDisplayName: displayName ?? adapter.appName,
                adapterIdentifier: adapter.appIdentifier,
                adapterName: adapter.appName,
                adapterSource: adapter.source
            )
        }

        let canonicalByID = Dictionary(
            uniqueKeysWithValues: snapshotProfile.shortcuts.map { ($0.id, $0) }
        )
        let shortcuts = adapter.mappings
            .compactMap { mapping -> AvailableShortcut? in
                guard mapping.isEnabled,
                      snapshotProfile.isShortcutEnabled(mapping.canonicalID),
                      snapshotProfile.isMappingEnabled(
                        adapterID: adapter.appIdentifier,
                        canonicalID: mapping.canonicalID
                      )
                else { return nil }
                guard let canonical = canonicalByID[mapping.canonicalID] else {
                    return nil
                }
                return AvailableShortcut(
                    id: canonical.id,
                    name: canonical.name,
                    defaultKeys: canonical.defaultKeys,
                    category: canonical.category,
                    actionKind: actionKind(for: mapping),
                    actionDescription: actionDescription(
                        for: mapping,
                        canonical: canonical,
                        adapter: adapter
                    ),
                    nativeKeys: mapping.nativeKeys,
                    menuTitle: mapping.menuTitle,
                    menuPath: mapping.menuPath,
                    axAction: mapping.axAction,
                    adapterSource: adapter.source
                )
            }
            .sorted { lhs, rhs in
                if lhs.category.availabilitySortOrder != rhs.category.availabilitySortOrder {
                    return lhs.category.availabilitySortOrder < rhs.category.availabilitySortOrder
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        return ShortcutAvailability(
            state: .available,
            appIdentifier: appID,
            appDisplayName: displayName ?? adapter.appName,
            adapterIdentifier: adapter.appIdentifier,
            adapterName: adapter.appName,
            adapterSource: adapter.source,
            shortcuts: shortcuts
        )
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

    public struct ResolvedShortcutAction: Equatable {
        public let appIdentifier: String
        public let canonicalID: String
        public let mapping: Adapter.Mapping
        public let action: ResolvedAction
        public let adapterSource: Adapter.Source
    }

    private struct ResolutionSnapshot {
        var comboToCanonicalID: [KeyCombo: String] = [:]
        var actionIndex: [String: [String: ResolvedAction]] = [:]
        var mappingIndex: [String: [String: Adapter.Mapping]] = [:]
        var sourceIndex: [String: Adapter.Source] = [:]
        var enabledAdapterIDs: Set<String> = []
    }

    private func actionKind(for mapping: Adapter.Mapping) -> AvailableShortcutActionKind {
        switch mapping.method {
        case .keyRemap:
            return .keyRemap
        case .menuInvoke:
            return .menuInvoke
        case .axAction:
            return .axAction
        case .passthrough:
            return .passthrough
        }
    }

    private func actionDescription(
        for mapping: Adapter.Mapping,
        canonical: CanonicalShortcut,
        adapter: Adapter
    ) -> String {
        switch mapping.method {
        case .keyRemap:
            guard let nativeKeys = mapping.nativeKeys else {
                return "Missing native shortcut"
            }
            return "Sends \(nativeKeys.displayString)"
        case .menuInvoke:
            guard let menuTitle = mapping.menuTitle else {
                return "Missing menu item"
            }
            return "Chooses \(menuTitle)"
        case .axAction:
            guard let axAction = mapping.axAction else {
                return "Missing Accessibility action"
            }
            return "Performs \(axAction)"
        case .passthrough:
            return "Uses \(canonical.defaultKeys.displayString) in \(adapter.appName)"
        }
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
        guard appIdentifier == adapter.appIdentifier,
              appIdentifier.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              appIdentifier.rangeOfCharacter(from: .controlCharacters) == nil
        else {
            throw AdapterValidationError.invalidAppIdentifier(adapter.appIdentifier)
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
        if let path = mapping.menuPath {
            guard !path.isEmpty,
                  path.count <= 8,
                  path.allSatisfy({
                      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          && $0.count <= 200
                          && !$0.contains("\0")
                  })
            else {
                throw AdapterValidationError.invalidContext(mapping.canonicalID)
            }
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
        stateLock.lock()
        adapters[adapter.appIdentifier] = adapter
        stateLock.unlock()
        rebuildActionIndex()
    }

    public func deleteUserAdapter(appIdentifier: String) throws {
        try deleteAdapter(appIdentifier: appIdentifier, from: userAdapterDirectory)
    }

    public func deleteAutoAdapter(appIdentifier: String) throws {
        try deleteAdapter(appIdentifier: appIdentifier, from: autoAdapterDirectory)
    }

    public func deleteEditableAdapter(appIdentifier: String) throws {
        if fileManager.fileExists(atPath: adapterURL(
            for: appIdentifier,
            in: userAdapterDirectory
        ).path) {
            try deleteUserAdapter(appIdentifier: appIdentifier)
        } else {
            try deleteAutoAdapter(appIdentifier: appIdentifier)
        }
    }

    public func exportAdapter(appIdentifier: String, to url: URL) throws {
        guard let adapter = adapter(for: appIdentifier) else {
            throw AdapterValidationError.invalidAppIdentifier(appIdentifier)
        }
        let data = try JSONEncoder.pretty.encode(adapter)
        try data.write(to: url, options: .atomic)
    }

    public func importUserAdapter(from url: URL) throws -> Adapter {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw AdapterValidationError.invalidAppIdentifier(url.lastPathComponent)
        }
        guard (values.fileSize ?? 0) <= Self.maxAdapterFileSize else {
            throw AdapterValidationError.fileTooLarge(values.fileSize ?? 0)
        }
        let data = try Data(contentsOf: url)
        let adapter = try JSONDecoder().decode(Adapter.self, from: data)
        try saveUserAdapter(adapter)
        return adapter
    }

    public func setAdapter(_ appIdentifier: String, enabled: Bool) {
        shortcutProfile.setAdapter(appIdentifier, enabled: enabled)
        rebuildActionIndex()
    }

    public func setMapping(
        adapterID: String,
        canonicalID: String,
        enabled: Bool
    ) {
        shortcutProfile.setMapping(
            adapterID: adapterID,
            canonicalID: canonicalID,
            enabled: enabled
        )
        rebuildActionIndex()
    }

    private func deleteAdapter(appIdentifier: String, from directory: URL) throws {
        let url = adapterURL(for: appIdentifier, in: directory)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        reloadAdapters()
    }

    private func adapterURL(for appIdentifier: String, in directory: URL) -> URL {
        directory
            .appendingPathComponent(safeAdapterFilename(for: appIdentifier))
            .appendingPathExtension("json")
    }

    /// Reload all adapters from disk (called after auto-generation saves a new one).
    public func reloadAdapters() {
        stateLock.lock()
        adapters.removeAll()
        validationMessages.removeAll()
        stateLock.unlock()
        loadAllAdapters()
    }

    public func applyShortcutProfile(_ profile: UserShortcutProfile) {
        stateLock.lock()
        shortcutProfile = profile
        canonicalShortcuts = profile.shortcuts
        stateLock.unlock()
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
            includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }

        let adapterFiles = contents.filter { $0.pathExtension == "json" }
        if adapterFiles.count > Self.maxAdapterFilesPerDirectory {
            appendValidationMessage(
                "\(directory.lastPathComponent): skipped because it contains \(adapterFiles.count) adapter files."
            )
            return
        }

        for fileURL in adapterFiles {
            do {
                let values = try fileURL.resourceValues(
                    forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey]
                )
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw AdapterValidationError.invalidAppIdentifier(fileURL.lastPathComponent)
                }
                let fileSize = values.fileSize ?? 0
                guard fileSize <= Self.maxAdapterFileSize else {
                    throw AdapterValidationError.fileTooLarge(fileSize)
                }

                let data = try Data(contentsOf: fileURL)
                let adapter = try JSONDecoder().decode(Adapter.self, from: data)
                try Self.validate(adapter: adapter, canonicals: canonicalShortcuts)
                noteShadowIfNeeded(adapter)
                stateLock.lock()
                adapters[adapter.appIdentifier] = adapter
                stateLock.unlock()
            } catch {
                let message = "\(fileURL.lastPathComponent): \(error)"
                appendValidationMessage(message)
                ShortyLog.adapterRegistry.warning("Skipped adapter \(message)")
                continue
            }
        }
    }

    private func rebuildComboIndex() {
        stateLock.lock()
        defer { stateLock.unlock() }
        comboToCanonicalID = [:]
        for shortcut in shortcutProfile.enabledShortcuts {
            comboToCanonicalID[shortcut.defaultKeys] = shortcut.id
        }
        rebuildResolutionSnapshotLocked()
    }

    private func rebuildActionIndex() {
        stateLock.lock()
        defer { stateLock.unlock() }
        var nextIndex: [String: [String: ResolvedAction]] = [:]
        var nextMappingIndex: [String: [String: Adapter.Mapping]] = [:]
        var nextSourceIndex: [String: Adapter.Source] = [:]
        for adapter in adapters.values {
            guard shortcutProfile.isAdapterEnabled(adapter.appIdentifier) else { continue }
            var mappingIndex: [String: ResolvedAction] = [:]
            var adapterMappingIndex: [String: Adapter.Mapping] = [:]
            for mapping in adapter.mappings {
                guard mapping.isEnabled,
                      shortcutProfile.isShortcutEnabled(mapping.canonicalID),
                      shortcutProfile.isMappingEnabled(
                        adapterID: adapter.appIdentifier,
                        canonicalID: mapping.canonicalID
                      )
                else { continue }
                guard let action = resolvedAction(for: mapping) else { continue }
                mappingIndex[mapping.canonicalID] = action
                adapterMappingIndex[mapping.canonicalID] = mapping
            }
            nextIndex[adapter.appIdentifier] = mappingIndex
            nextMappingIndex[adapter.appIdentifier] = adapterMappingIndex
            nextSourceIndex[adapter.appIdentifier] = adapter.source
        }
        actionIndex = nextIndex
        self.mappingIndex = nextMappingIndex
        sourceIndex = nextSourceIndex
        rebuildResolutionSnapshotLocked()
    }

    private func rebuildResolutionSnapshotLocked() {
        resolutionSnapshot = ResolutionSnapshot(
            comboToCanonicalID: comboToCanonicalID,
            actionIndex: actionIndex,
            mappingIndex: mappingIndex,
            sourceIndex: sourceIndex,
            enabledAdapterIDs: Set(actionIndex.keys)
        )
    }

    private func currentResolutionSnapshot() -> ResolutionSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return resolutionSnapshot
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

    private func appendValidationMessage(_ message: String) {
        stateLock.lock()
        validationMessages.append(message)
        stateLock.unlock()
    }

    private func noteShadowIfNeeded(_ adapter: Adapter) {
        stateLock.lock()
        let existing = adapters[adapter.appIdentifier]
        stateLock.unlock()

        guard let existing, existing.source != adapter.source else { return }
        appendValidationMessage(
            "\(adapter.appIdentifier): \(adapter.source.rawValue) adapter overrides \(existing.source.rawValue) adapter."
        )
    }

    // MARK: - Built-in adapter catalog

    private func loadHardcodedAdapters() {
        let builtins = Self.builtinAdapters
        // Only insert if not already loaded from JSON.
        for adapter in builtins where adapters[adapter.appIdentifier] == nil {
            do {
                try Self.validate(adapter: adapter, canonicals: canonicalShortcuts)
                stateLock.lock()
                adapters[adapter.appIdentifier] = adapter
                stateLock.unlock()
            } catch {
                let message = "\(adapter.appIdentifier): \(error)"
                appendValidationMessage(message)
                ShortyLog.adapterRegistry.error("Invalid built-in adapter \(message)")
            }
        }
    }

    static let commonBrowserMappings: [Adapter.Mapping] = [
        passthrough("focus_url_bar"),
        passthrough("go_back"),
        passthrough("go_forward"),
        passthrough("select_all"),
        passthrough("find_in_page"),
        passthrough("new_tab"),
        passthrough("close_tab"),
        passthrough("next_tab"),
        passthrough("prev_tab"),
        passthrough("reopen_tab"),
        passthrough("new_window"),
        passthrough("close_window"),
        passthrough("minimize_window")
    ]

    static let commonDocumentMappings: [Adapter.Mapping] = [
        passthrough("select_all"),
        passthrough("find_in_page"),
        passthrough("newline_in_field"),
        passthrough("new_window"),
        passthrough("close_window"),
        passthrough("minimize_window")
    ]

    static let commonChatMappings: [Adapter.Mapping] = [
        passthrough("submit_field"),
        passthrough("newline_in_field"),
        passthrough("find_in_page"),
        remap("command_palette", to: "cmd+k"),
        passthrough("spotlight_search"),
        passthrough("new_window"),
        passthrough("close_window"),
        passthrough("minimize_window")
    ]

    static let commonTerminalMappings: [Adapter.Mapping] = [
        passthrough("newline_in_field"),
        passthrough("find_in_page"),
        passthrough("new_tab"),
        passthrough("close_tab"),
        passthrough("new_window"),
        passthrough("close_window"),
        passthrough("minimize_window")
    ]

    static let commonCodeEditorMappings: [Adapter.Mapping] = [
        remap("focus_url_bar", to: "cmd+p"),
        remap("spotlight_search", to: "cmd+p"),
        remap("command_palette", to: "cmd+shift+p"),
        passthrough("select_all"),
        passthrough("find_in_page"),
        remap("find_and_replace", to: "cmd+option+f"),
        passthrough("newline_in_field"),
        passthrough("new_tab"),
        passthrough("close_tab"),
        passthrough("new_window"),
        passthrough("close_window"),
        passthrough("minimize_window")
    ]

    static let commonMediaMappings: [Adapter.Mapping] = [
        passthrough("toggle_play_pause"),
        passthrough("find_in_page"),
        passthrough("new_window"),
        passthrough("close_window"),
        passthrough("minimize_window")
    ]

    static let builtinAdapters: [Adapter] = [
        adapter("com.apple.Safari", "Safari", commonBrowserMappings),
        adapter("com.google.Chrome", "Google Chrome", commonBrowserMappings),
        adapter("com.google.Chrome.canary", "Google Chrome Canary", commonBrowserMappings),
        adapter("org.chromium.Chromium", "Chromium", commonBrowserMappings),
        adapter("com.brave.Browser", "Brave Browser", commonBrowserMappings),
        adapter("com.microsoft.edgemac", "Microsoft Edge", commonBrowserMappings),
        adapter("com.vivaldi.Vivaldi", "Vivaldi", commonBrowserMappings),
        adapter("org.mozilla.firefox", "Firefox", commonBrowserMappings),
        adapter(
            "company.thebrowser.Browser",
            "Arc",
            mappings(
                commonBrowserMappings,
                [remap("command_palette", to: "cmd+t")]
            )
        ),
        adapter(
            "com.openai.atlas",
            "ChatGPT Atlas",
            mappings(commonBrowserMappings, [passthrough("spotlight_search")])
        ),

        adapter("com.microsoft.VSCode", "Visual Studio Code", commonCodeEditorMappings),
        adapter(
            "com.microsoft.VSCodeInsiders",
            "Visual Studio Code - Insiders",
            commonCodeEditorMappings
        ),
        adapter("dev.zed.Zed", "Zed", commonCodeEditorMappings),
        adapter("dev.zed.Zed-Preview", "Zed Preview", commonCodeEditorMappings),
        adapter("com.google.antigravity", "Antigravity", commonCodeEditorMappings),
        adapter(
            "com.apple.dt.Xcode",
            "Xcode",
            mappings(
                commonCodeEditorMappings,
                [
                    remap("focus_url_bar", to: "cmd+shift+o"),
                    remap("spotlight_search", to: "cmd+shift+o"),
                    remap("command_palette", to: "cmd+shift+o")
                ]
            )
        ),

        adapter("com.apple.Terminal", "Terminal", commonTerminalMappings),
        adapter("com.googlecode.iterm2", "iTerm2", commonTerminalMappings),
        adapter("com.mitchellh.ghostty", "Ghostty", commonTerminalMappings),
        adapter("com.termius.mac", "Termius", commonTerminalMappings),
        adapter("com.termius-beta.mac", "Termius Beta", commonTerminalMappings),

        adapter(
            "com.apple.finder",
            "Finder",
            mappings(
                commonDocumentMappings,
                [
                    remap("focus_url_bar", to: "cmd+shift+g"),
                    passthrough("new_tab")
                ]
            )
        ),
        adapter(
            "com.apple.TextEdit",
            "TextEdit",
            mappings(commonDocumentMappings, [remap("find_and_replace", to: "cmd+option+f")])
        ),
        adapter("com.apple.Notes", "Notes", commonDocumentMappings),
        adapter(
            "com.apple.mail",
            "Mail",
            mappings(
                commonDocumentMappings,
                [remap("submit_field", to: "cmd+shift+return", context: "message-compose")]
            )
        ),
        adapter(
            "com.apple.MobileSMS",
            "Messages",
            mappings(
                commonChatMappings,
                [remap("newline_in_field", to: "option+return", context: "text-entry")]
            )
        ),
        adapter("com.apple.Preview", "Preview", commonDocumentMappings),
        adapter("com.apple.iCal", "Calendar", commonDocumentMappings),
        adapter(
            "com.apple.Maps",
            "Maps",
            mappings(commonDocumentMappings, [remap("focus_url_bar", to: "cmd+f")])
        ),
        adapter("com.apple.FaceTime", "FaceTime", commonDocumentMappings),
        adapter(
            "com.apple.AddressBook",
            "Contacts",
            mappings(commonDocumentMappings, [remap("focus_url_bar", to: "cmd+f")])
        ),
        adapter("com.apple.mobilephone", "Phone", commonChatMappings),
        adapter("com.apple.weather", "Weather", commonDocumentMappings),
        adapter("com.apple.AppStore", "App Store", commonDocumentMappings),
        adapter("com.apple.ActivityMonitor", "Activity Monitor", commonDocumentMappings),
        adapter("com.apple.Music", "Music", commonMediaMappings),
        adapter("com.apple.podcasts", "Podcasts", commonMediaMappings),

        adapter("com.openai.chat", "ChatGPT", commonChatMappings),
        adapter("com.openai.codex", "Codex", commonChatMappings),
        adapter("com.anthropic.claudefordesktop", "Claude", commonChatMappings),
        adapter("com.electron.ollama", "Ollama", commonChatMappings),
        adapter("org.whispersystems.signal-desktop", "Signal", commonChatMappings),
        adapter("net.whatsapp.WhatsApp", "WhatsApp", commonChatMappings),
        adapter("us.zoom.xos", "Zoom", commonDocumentMappings),
        adapter(
            "com.tinyspeck.slackmacgap",
            "Slack",
            mappings(
                commonChatMappings,
                [remap("newline_in_field", to: "option+return", context: "text-entry")]
            )
        ),
        adapter("com.hnc.Discord", "Discord", commonChatMappings),
        adapter("ru.keepcoder.Telegram", "Telegram", commonChatMappings),

        adapter(
            "notion.id",
            "Notion",
            mappings(
                commonDocumentMappings,
                [
                    remap("command_palette", to: "cmd+p"),
                    remap("spotlight_search", to: "cmd+p")
                ]
            )
        ),
        adapter("notion.mail.id", "Notion Mail", commonChatMappings),
        adapter("com.cron.electron", "Notion Calendar", commonDocumentMappings),
        adapter(
            "md.obsidian",
            "Obsidian",
            mappings(
                commonDocumentMappings,
                [
                    remap("focus_url_bar", to: "cmd+o"),
                    remap("command_palette", to: "cmd+p"),
                    remap("spotlight_search", to: "cmd+o")
                ]
            )
        ),
        adapter("com.iconfactory.Tot", "Tot", commonDocumentMappings),
        adapter(
            "com.raycast.macos",
            "Raycast",
            mappings(
                commonDocumentMappings,
                [
                    remap("command_palette", to: "cmd+k"),
                    passthrough("spotlight_search")
                ]
            )
        ),
        adapter("com.culturedcode.ThingsMac", "Things 3", commonDocumentMappings),
        adapter("com.omnigroup.OmniFocus4", "OmniFocus", commonDocumentMappings),
        adapter("com.ngocluu.goodlinks", "GoodLinks", commonDocumentMappings),
        adapter("com.lukilabs.lukiapp", "Craft", commonDocumentMappings),
        adapter("com.zettlr.app", "Zettlr", commonDocumentMappings),
        adapter("org.zotero.zotero", "Zotero", commonDocumentMappings),
        adapter("org.zotero.zotero-beta", "Zotero", commonDocumentMappings),
        adapter("com.github.GitHubClient", "GitHub Desktop", commonDocumentMappings),
        adapter("io.httpie.desktop", "HTTPie", commonDocumentMappings),
        adapter(
            "com.1password.1password",
            "1Password",
            mappings(commonDocumentMappings, [passthrough("spotlight_search")])
        ),
        adapter(
            "com.figma.Desktop",
            "Figma",
            mappings(
                commonDocumentMappings,
                [
                    remap("command_palette", to: "cmd+/"),
                    remap("spotlight_search", to: "cmd+/")
                ]
            )
        ),
        adapter("com.tldraw.desktop", "tldraw", commonDocumentMappings),
        adapter(
            "com.spotify.client",
            "Spotify",
            mappings(commonMediaMappings, [remap("find_in_page", to: "cmd+l")])
        ),

        adapter("com.microsoft.Word", "Microsoft Word", commonDocumentMappings),
        adapter("com.microsoft.Excel", "Microsoft Excel", commonDocumentMappings),
        adapter("com.microsoft.Powerpoint", "Microsoft PowerPoint", commonDocumentMappings),
        adapter("com.apple.iWork.Pages", "Pages", commonDocumentMappings),
        adapter("com.apple.iWork.Numbers", "Numbers", commonDocumentMappings),
        adapter("com.apple.iWork.Keynote", "Keynote", commonDocumentMappings),

        adapter(
            "web:notion.so",
            "Notion Web",
            mappings(
                commonBrowserMappings,
                [
                    remap("command_palette", to: "cmd+p"),
                    remap("spotlight_search", to: "cmd+p"),
                    passthrough("newline_in_field")
                ]
            )
        ),
        adapter(
            "web:slack.com",
            "Slack Web",
            mappings(
                commonBrowserMappings,
                commonChatMappings,
                [remap("newline_in_field", to: "option+return", context: "text-entry")]
            )
        ),
        adapter(
            "web:mail.google.com",
            "Gmail Web",
            mappings(
                commonBrowserMappings,
                [
                    remap("submit_field", to: "cmd+return", context: "message-compose"),
                    passthrough("newline_in_field")
                ]
            )
        ),
        adapter(
            "web:docs.google.com",
            "Google Docs Web",
            mappings(commonBrowserMappings, [passthrough("find_and_replace"), passthrough("newline_in_field")])
        ),
        adapter(
            "web:figma.com",
            "Figma Web",
            mappings(
                commonBrowserMappings,
                [
                    remap("command_palette", to: "cmd+/"),
                    remap("spotlight_search", to: "cmd+/")
                ]
            )
        ),
        adapter(
            "web:linear.app",
            "Linear Web",
            mappings(
                commonBrowserMappings,
                [
                    remap("command_palette", to: "cmd+k"),
                    passthrough("spotlight_search")
                ]
            )
        ),
        adapter("com.linear", "Linear", mappings(commonDocumentMappings, commonChatMappings)),
        adapter(
            "web:chatgpt.com",
            "ChatGPT Web",
            mappings(commonBrowserMappings, commonChatMappings)
        ),
        adapter(
            "web:claude.ai",
            "Claude Web",
            mappings(commonBrowserMappings, commonChatMappings)
        ),
        adapter("web:github.com", "GitHub Web", commonBrowserMappings),
        adapter("web:calendar.google.com", "Google Calendar Web", commonBrowserMappings),
        adapter("web:drive.google.com", "Google Drive Web", commonBrowserMappings),
        adapter("web:sheets.google.com", "Google Sheets Web", commonBrowserMappings),
        adapter("web:slides.google.com", "Google Slides Web", commonBrowserMappings),
        adapter("web:meet.google.com", "Google Meet Web", commonBrowserMappings),
        adapter("web:whatsapp.com", "WhatsApp Web", mappings(commonBrowserMappings, commonChatMappings))
    ]

    private static func adapter(
        _ appIdentifier: String,
        _ appName: String,
        _ mappings: [Adapter.Mapping]
    ) -> Adapter {
        Adapter(
            appIdentifier: appIdentifier,
            appName: appName,
            mappings: mappings
        )
    }

    private static func mappings(_ groups: [Adapter.Mapping]...) -> [Adapter.Mapping] {
        var merged: [Adapter.Mapping] = []
        var indexesByCanonicalID: [String: Int] = [:]

        for mapping in groups.flatMap({ $0 }) {
            if let index = indexesByCanonicalID[mapping.canonicalID] {
                merged[index] = mapping
            } else {
                indexesByCanonicalID[mapping.canonicalID] = merged.count
                merged.append(mapping)
            }
        }

        return merged
    }

    private static func passthrough(_ canonicalID: String) -> Adapter.Mapping {
        Adapter.Mapping(canonicalID: canonicalID, method: .passthrough)
    }

    private static func remap(
        _ canonicalID: String,
        to nativeKeys: String,
        context: String? = nil
    ) -> Adapter.Mapping {
        Adapter.Mapping(
            canonicalID: canonicalID,
            method: .keyRemap,
            nativeKeys: keyCombo(nativeKeys),
            context: context
        )
    }

    private static func keyCombo(_ string: String) -> KeyCombo {
        guard let combo = KeyCombo(from: string) else {
            preconditionFailure("Invalid built-in key combo: \(string)")
        }
        return combo
    }
}

// MARK: - JSON encoder helper

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
