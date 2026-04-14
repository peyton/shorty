import Foundation

/// A user-facing "intent" — a semantic action with a default key binding.
///
/// Canonical shortcuts are the core abstraction: users think in terms of
/// *what they want to do* ("focus URL bar"), not *which keys to press*.
/// The engine translates each canonical shortcut into the correct native
/// key combo for the frontmost app.
public struct CanonicalShortcut: Codable, Identifiable, Hashable {
    /// Stable machine identifier, e.g. "focus_url_bar".
    public let id: String

    /// Human-readable name shown in the UI.
    public let name: String

    /// The default key combo the user presses everywhere.
    public let defaultKeys: KeyCombo

    /// Grouping category for the settings UI.
    public let category: Category

    /// One-line description of what this shortcut does.
    public let description: String

    public init(
        id: String,
        name: String,
        defaultKeys: KeyCombo,
        category: Category,
        description: String
    ) {
        self.id = id
        self.name = name
        self.defaultKeys = defaultKeys
        self.category = category
        self.description = description
    }
}

// MARK: - Category

extension CanonicalShortcut {
    public enum Category: String, Codable, CaseIterable, Hashable {
        case navigation
        case editing
        case tabs
        case windows
        case search
        case media
        case system
    }
}

// MARK: - Built-in Defaults

extension CanonicalShortcut {
    /// The default set of canonical shortcuts that Shorty ships with.
    /// Users can customize these, but these represent the "one set to rule them all."
    public static let defaults: [CanonicalShortcut] = [
        // Navigation
        CanonicalShortcut(
            id: "focus_url_bar",
            name: "Focus URL / Address Bar",
            defaultKeys: KeyCombo(keyCode: 0x25, modifiers: .command), // Cmd+L
            category: .navigation,
            description: "Focus the URL bar, address bar, or location input"
        ),
        CanonicalShortcut(
            id: "go_back",
            name: "Go Back",
            defaultKeys: KeyCombo(keyCode: 0x7B, modifiers: [.command]), // Cmd+Left
            category: .navigation,
            description: "Navigate back in history"
        ),
        CanonicalShortcut(
            id: "go_forward",
            name: "Go Forward",
            defaultKeys: KeyCombo(keyCode: 0x7C, modifiers: [.command]), // Cmd+Right
            category: .navigation,
            description: "Navigate forward in history"
        ),

        // Editing
        CanonicalShortcut(
            id: "newline_in_field",
            name: "Newline in Text Field",
            defaultKeys: KeyCombo(keyCode: 0x24, modifiers: .shift), // Shift+Enter
            category: .editing,
            description: "Insert a newline without submitting/sending"
        ),
        CanonicalShortcut(
            id: "submit_field",
            name: "Submit / Send",
            defaultKeys: KeyCombo(keyCode: 0x24, modifiers: []), // Enter
            category: .editing,
            description: "Submit the form or send the message"
        ),
        CanonicalShortcut(
            id: "select_all",
            name: "Select All",
            defaultKeys: KeyCombo(keyCode: 0x00, modifiers: .command), // Cmd+A
            category: .editing,
            description: "Select all content"
        ),
        CanonicalShortcut(
            id: "find_in_page",
            name: "Find in Page",
            defaultKeys: KeyCombo(keyCode: 0x03, modifiers: .command), // Cmd+F
            category: .search,
            description: "Open the find/search bar within the current view"
        ),
        CanonicalShortcut(
            id: "find_and_replace",
            name: "Find and Replace",
            defaultKeys: KeyCombo(keyCode: 0x03, modifiers: [.command, .shift]), // Cmd+Shift+F
            category: .search,
            description: "Open find and replace"
        ),

        // Tabs
        CanonicalShortcut(
            id: "new_tab",
            name: "New Tab",
            defaultKeys: KeyCombo(keyCode: 0x11, modifiers: .command), // Cmd+T
            category: .tabs,
            description: "Open a new tab"
        ),
        CanonicalShortcut(
            id: "close_tab",
            name: "Close Tab",
            defaultKeys: KeyCombo(keyCode: 0x0D, modifiers: .command), // Cmd+W
            category: .tabs,
            description: "Close the current tab"
        ),
        CanonicalShortcut(
            id: "next_tab",
            name: "Next Tab",
            defaultKeys: KeyCombo(keyCode: 0x30, modifiers: [.control]), // Ctrl+Tab
            category: .tabs,
            description: "Switch to the next tab"
        ),
        CanonicalShortcut(
            id: "prev_tab",
            name: "Previous Tab",
            defaultKeys: KeyCombo(keyCode: 0x30, modifiers: [.control, .shift]), // Ctrl+Shift+Tab
            category: .tabs,
            description: "Switch to the previous tab"
        ),
        CanonicalShortcut(
            id: "reopen_tab",
            name: "Reopen Closed Tab",
            defaultKeys: KeyCombo(keyCode: 0x11, modifiers: [.command, .shift]), // Cmd+Shift+T
            category: .tabs,
            description: "Reopen the most recently closed tab"
        ),

        // Windows
        CanonicalShortcut(
            id: "new_window",
            name: "New Window",
            defaultKeys: KeyCombo(keyCode: 0x2D, modifiers: .command), // Cmd+N
            category: .windows,
            description: "Open a new window"
        ),
        CanonicalShortcut(
            id: "close_window",
            name: "Close Window",
            defaultKeys: KeyCombo(keyCode: 0x0D, modifiers: [.command, .shift]), // Cmd+Shift+W
            category: .windows,
            description: "Close the current window"
        ),
        CanonicalShortcut(
            id: "minimize_window",
            name: "Minimize Window",
            defaultKeys: KeyCombo(keyCode: 0x2E, modifiers: .command), // Cmd+M
            category: .windows,
            description: "Minimize the current window"
        ),

        // Search
        CanonicalShortcut(
            id: "command_palette",
            name: "Command Palette / Quick Open",
            defaultKeys: KeyCombo(keyCode: 0x23, modifiers: [.command, .shift]), // Cmd+Shift+P
            category: .search,
            description: "Open the command palette or quick-open dialog"
        ),
        CanonicalShortcut(
            id: "spotlight_search",
            name: "Search Everything",
            defaultKeys: KeyCombo(keyCode: 0x2F, modifiers: .command), // Cmd+.  — actually let's use Cmd+K
            category: .search,
            description: "Global search or spotlight within the app"
        ),

        // Media
        CanonicalShortcut(
            id: "toggle_play_pause",
            name: "Play / Pause",
            defaultKeys: KeyCombo(keyCode: 0x31, modifiers: []), // Space
            category: .media,
            description: "Toggle play/pause in media apps"
        )
    ]
}
