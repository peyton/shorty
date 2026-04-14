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
    public static let minimumScore: Double = 0.70

    /// Reject matches when the best two candidates are too close.
    public static let ambiguityMargin: Double = 0.20

    public struct Match {
        public let item: MenuIntrospector.DiscoveredMenuItem
        public let score: Double
        public let reason: Reason
    }

    public enum Reason: String {
        case exactAlias
        case exactKeyCombo
        case keywordOverlap
    }

    private struct Candidate {
        let match: Match
    }

    public init() {}

    /// Find the best-matching menu item for a canonical shortcut.
    public func bestMatch(
        for canonical: CanonicalShortcut,
        among items: [MenuIntrospector.DiscoveredMenuItem]
    ) -> Match? {
        let candidates = items
            .map { candidate(canonical: canonical, item: $0) }
            .sorted { $0.match.score > $1.match.score }

        guard let best = candidates.first else {
            return nil
        }

        guard best.match.score >= Self.minimumScore else {
            return nil
        }

        if let second = candidates.dropFirst().first,
           best.match.score - second.match.score < Self.ambiguityMargin {
            return nil
        }

        return best.match
    }

    // MARK: - Scoring

    private func candidate(
        canonical: CanonicalShortcut,
        item: MenuIntrospector.DiscoveredMenuItem
    ) -> Candidate {
        let aliasScore = aliasScore(canonical: canonical, item: item)
        let keywordScore = keywordScore(canonical: canonical, item: item)
        let keyComboScore = keyComboScore(canonical: canonical, item: item)

        let score = min(aliasScore + keywordScore + keyComboScore, 1.0)
        let reason: Reason
        if keyComboScore > 0 {
            reason = .exactKeyCombo
        } else if aliasScore > 0 {
            reason = .exactAlias
        } else {
            reason = .keywordOverlap
        }

        return Candidate(match: Match(item: item, score: score, reason: reason))
    }

    private func aliasScore(
        canonical: CanonicalShortcut,
        item: MenuIntrospector.DiscoveredMenuItem
    ) -> Double {
        if let aliases = Self.aliasTable[canonical.id] {
            let itemLower = item.title.lowercased()
            for alias in aliases where itemLower.contains(alias.lowercased()) {
                return 0.8
            }
        }

        return 0
    }

    private func keywordScore(
        canonical: CanonicalShortcut,
        item: MenuIntrospector.DiscoveredMenuItem
    ) -> Double {
        let canonicalWords = tokenize(canonical.name + " " + canonical.description)
        let itemWords = tokenize(item.title)
        let overlap = Double(canonicalWords.intersection(itemWords).count)
        let maxPossible = Double(max(canonicalWords.count, 1))
        return (overlap / maxPossible) * 0.5
    }

    private func keyComboScore(
        canonical: CanonicalShortcut,
        item: MenuIntrospector.DiscoveredMenuItem
    ) -> Double {
        if let itemCombo = item.keyCombo, itemCombo == canonical.defaultKeys {
            return 0.75
        }
        return 0
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
            "go to address", "focus address"
        ],
        "go_back": [
            "back", "go back", "navigate back", "previous page"
        ],
        "go_forward": [
            "forward", "go forward", "navigate forward", "next page"
        ],
        "new_tab": [
            "new tab"
        ],
        "close_tab": [
            "close tab", "close current tab"
        ],
        "next_tab": [
            "next tab", "select next tab", "show next tab"
        ],
        "prev_tab": [
            "previous tab", "select previous tab", "show previous tab"
        ],
        "reopen_tab": [
            "reopen closed tab", "reopen last closed tab",
            "undo close tab", "restore tab"
        ],
        "new_window": [
            "new window"
        ],
        "close_window": [
            "close window", "close all"
        ],
        "minimize_window": [
            "minimize"
        ],
        "find_in_page": [
            "find", "search", "find in page"
        ],
        "find_and_replace": [
            "find and replace", "replace", "find & replace"
        ],
        "select_all": [
            "select all"
        ],
        "command_palette": [
            "command palette", "quick open", "go to file",
            "show all commands", "action search"
        ],
        "spotlight_search": [
            "search", "quick find", "spotlight"
        ],
        "toggle_play_pause": [
            "play", "pause", "play/pause", "play pause"
        ],
        "newline_in_field": [
            // Usually not a menu item — handled by keyRemap
        ],
        "submit_field": [
            // Usually not a menu item — handled by keyRemap
        ]
    ]
}
