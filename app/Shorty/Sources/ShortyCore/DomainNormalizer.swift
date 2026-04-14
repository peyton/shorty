import Foundation

/// Converts browser-reported hosts into stable web adapter identifiers.
public enum DomainNormalizer {
    /// Return the adapter identifier used by `AdapterRegistry`.
    public static func adapterIdentifier(for host: String) -> String {
        "web:\(normalizedDomain(for: host))"
    }

    /// Collapse known subdomains to the supported web app domain.
    public static func normalizedDomain(for host: String) -> String {
        let cleaned = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let withoutWWW = cleaned.hasPrefix("www.")
            ? String(cleaned.dropFirst(4))
            : cleaned

        if matches(withoutWWW, root: "notion.so") {
            return "notion.so"
        }
        if matches(withoutWWW, root: "slack.com") {
            return "slack.com"
        }
        if withoutWWW == "mail.google.com" {
            return "mail.google.com"
        }
        if withoutWWW == "docs.google.com" {
            return "docs.google.com"
        }
        if matches(withoutWWW, root: "figma.com") {
            return "figma.com"
        }
        if matches(withoutWWW, root: "linear.app") {
            return "linear.app"
        }

        return withoutWWW
    }

    private static func matches(_ host: String, root: String) -> Bool {
        host == root || host.hasSuffix(".\(root)")
    }
}
