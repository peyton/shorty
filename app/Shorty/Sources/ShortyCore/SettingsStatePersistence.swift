import Foundation

/// Persists UI state for the Settings window across sessions.
public struct PersistedSettingsState: Codable, Equatable {
    public static let defaultsKey = "Shorty.Settings.UIState"

    public var lastSelectedTab: String?
    public var lastSelectedCategory: String?
    public var showsDetailsInPopover: Bool
    public var compactPopoverMode: Bool
    public var translationSoundEnabled: Bool
    public var weeklyDigestEnabled: Bool
    public var showTranslationToasts: Bool
    public var toastsShownCount: Int

    public init(
        lastSelectedTab: String? = nil,
        lastSelectedCategory: String? = nil,
        showsDetailsInPopover: Bool = false,
        compactPopoverMode: Bool = false,
        translationSoundEnabled: Bool = false,
        weeklyDigestEnabled: Bool = false,
        showTranslationToasts: Bool = true,
        toastsShownCount: Int = 0
    ) {
        self.lastSelectedTab = lastSelectedTab
        self.lastSelectedCategory = lastSelectedCategory
        self.showsDetailsInPopover = showsDetailsInPopover
        self.compactPopoverMode = compactPopoverMode
        self.translationSoundEnabled = translationSoundEnabled
        self.weeklyDigestEnabled = weeklyDigestEnabled
        self.showTranslationToasts = showTranslationToasts
        self.toastsShownCount = toastsShownCount
    }

    /// Whether to show toast notifications (auto-disables after first few uses).
    public var shouldShowToasts: Bool {
        showTranslationToasts && toastsShownCount < 20
    }

    public mutating func recordToastShown() {
        toastsShownCount += 1
    }

    public static func load(userDefaults: UserDefaults = .standard) -> PersistedSettingsState {
        guard let data = userDefaults.data(forKey: defaultsKey),
              let state = try? JSONDecoder().decode(PersistedSettingsState.self, from: data)
        else {
            return PersistedSettingsState()
        }
        return state
    }

    public func save(userDefaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        userDefaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Tracks settings changes for undo support.
public final class SettingsUndoStack: ObservableObject {
    public static let maxUndoDepth = 20

    @Published public private(set) var canUndo: Bool = false
    @Published public private(set) var undoDescription: String?

    private var stack: [SettingsChange] = []

    public init() {}

    public func push(_ change: SettingsChange) {
        stack.append(change)
        if stack.count > Self.maxUndoDepth {
            stack.removeFirst()
        }
        canUndo = !stack.isEmpty
        undoDescription = change.description
    }

    public func pop() -> SettingsChange? {
        guard let change = stack.popLast() else { return nil }
        canUndo = !stack.isEmpty
        undoDescription = stack.last?.description
        return change
    }

    public func clear() {
        stack.removeAll()
        canUndo = false
        undoDescription = nil
    }
}

/// A reversible settings change.
public struct SettingsChange {
    public enum Kind {
        case shortcutEnabled(id: String, wasEnabled: Bool)
        case shortcutKeyCombo(id: String, previousKeys: KeyCombo)
        case adapterEnabled(appID: String, wasEnabled: Bool)
        case mappingEnabled(adapterID: String, canonicalID: String, wasEnabled: Bool)
        case adapterDeleted(adapter: Adapter)
    }

    public let kind: Kind
    public let description: String
    public let timestamp: Date

    public init(kind: Kind, description: String, timestamp: Date = Date()) {
        self.kind = kind
        self.description = description
        self.timestamp = timestamp
    }
}
