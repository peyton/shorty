import Foundation

/// Fuzzy-matches canonical shortcut intents to discovered menu items.
///
/// Uses a multi-signal scoring approach:
/// 1. **Keyword match** — overlap between the canonical name/description
///    and the menu item title.
/// 2. **Key combo match** — if the discovered item's shortcut matches
///    the canonical default, it's almost certainly the right one.
/// 3. **Alias table** — hand-curated synonyms for common intents
///    (e.g., "Open Location…" → focus_url_bar).
///
/// Phase 4 will add an LLM call as a fallback for ambiguous matches.
public struct IntentMatcher {

    /// Minimum score to consider a match valid.
    private let threshold: Double = 0.3

    public init() {}

    /// Find the best-matching menu item for a canonical shortcut.
    public func bestMatch(
        for canonical: CanonicalShortcut,
        among items: [MenuIntrospector.DiscoveredMenuItem]
    ) -> MenuIntrospector.DiscoveredMenuItem? {
        var bestItem: MenuIntrospector.DiscoveredMenuItem?
        var bestScore: Double = 0

        for item in items {
            let score = self.score(canonical: canonical, item: item)
            if score > bestScore {
                bestScore = score
                bestItem = item
            }
        }

        return bestScore >= threshold ? bestItem : nil
    }

    // MARK: - Scoring

    private func score(
        canonical: CanonicalShortcut,
        item: MenuIntrospector.DiscoveredMenuItem
    ) -> Double {
        var total: Double = 0

        // 1. Alias table (highest priority — hand-curated knowledge).
        if let aliases = Self.aliasTable[canonical.id] {
            let itemLower = item.title.lowercased()
            for alias in aliases {
                if itemLower.contains(alias.lowercased()) {
                    total += 0.8
                    break
                }
            }
        }

        // 2. Keyword overlap between canonical name+description and item title.
        let canonicalWords = tokenize(canonical.name + " " + canonical.description)
        let itemWords = tokenize(item.title)
        let overlap = Double(canonicalWords.intersection(itemWords).count)
        let maxPossible = Double(max(canonicalWords.count, 1))
        total += (overlap / maxPossible) * 0.5

        // 3. Key combo match — strong signal.
        if let itemCombo = item.keyCombo, itemCombo == canonical.defaultKeys {
            total += 0.6
        }

        // Clamp to [0, 1]
        return min(total, 1.0)
    }

    // MARK: - Tokenization

    private func tokenize(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 } // drop single chars
        return Set(words)
    }

    // MARK: - Alias table

    /// Maps canonical IDs to known menu item title fragments.
    /// These are common patterns across many apps.
    private static let aliasTable: [String: [String]] = [
        "focus_url_bar": [
            "open location", "address bar", "url bar",
            "go to address", "focus address",
        ],
        "go_back": [
            "back", "go back", "navigate back", "previous page",
        ],
        "go_forward": [
            "forward", "go forward", "navigate forward", "next page",
        ],
        "new_tab": [
            "new tab",
        ],
        "close_tab": [
            "close tab", "close current tab",
        ],
        "next_tab": [
            "next tab", "select next tab", "show next tab",
        ],
        "prev_tab": [
            "previous tab", "select previous tab", "show previous tab",
        ],
        "reopen_tab": [
            "reopen closed tab", "reopen last closed tab",
            "undo close tab", "restore tab",
        ],
        "new_window": [
            "new window",
        ],
        "close_window": [
            "close window", "close all",
        ],
        "minimize_window": [
            "minimize",
        ],
        "find_in_page": [
            "find", "search", "find in page",
        ],
        "find_and_replace": [
            "find and replace", "replace", "find & replace",
        ],
        "select_all": [
            "select all",
        ],
        "command_palette": [
            "command palette", "quick open", "go to file",
            "show all commands", "action search",
        ],
        "spotlight_search": [
            "search", "quick find", "spotlight",
        ],
        "toggle_play_pause": [
            "play", "pause", "play/pause", "play pause",
        ],
        "newline_in_field": [
            // Usually not a menu item — handled by keyRemap
        ],
        "submit_field": [
            // Usually not a menu item — handled by keyRemap
        ],
    ]
}
