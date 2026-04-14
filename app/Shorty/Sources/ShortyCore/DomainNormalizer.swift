import Foundation

/// Converts browser-reported hosts into stable web adapter identifiers.
public enum DomainNormalizer {
    private static let exactDomainMatches: Set<String> = [
        "mail.google.com",
        "docs.google.com",
        "calendar.google.com",
        "drive.google.com",
        "sheets.google.com",
        "slides.google.com",
        "meet.google.com"
    ]

    private static let rootDomainMatches: Set<String> = [
        "notion.so",
        "slack.com",
        "figma.com",
        "linear.app",
        "chatgpt.com",
        "claude.ai",
        "github.com",
        "whatsapp.com"
    ]

    public static let supportedWebAppDomains = exactDomainMatches
        .union(rootDomainMatches)

    /// Return the adapter identifier used by `AdapterRegistry`.
    public static func adapterIdentifier(for host: String) -> String {
        "web:\(normalizedDomain(for: host))"
    }

    public static func supportedNormalizedDomain(for host: String) -> String? {
        let normalized = normalizedDomain(for: host)
        return supportedWebAppDomains.contains(normalized) ? normalized : nil
    }

    public static func isSupportedWebAppDomain(_ host: String) -> Bool {
        supportedNormalizedDomain(for: host) != nil
    }

    /// Collapse known subdomains to the supported web app domain.
    public static func normalizedDomain(for host: String) -> String {
        let cleaned = hostOnly(from: host)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let withoutWWW = cleaned.hasPrefix("www.")
            ? String(cleaned.dropFirst(4))
            : cleaned

        if exactDomainMatches.contains(withoutWWW) {
            return withoutWWW
        }

        if let root = rootDomainMatches.first(where: { matches(withoutWWW, root: $0) }) {
            return root
        }

        return withoutWWW
    }

    private static func hostOnly(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let parsedHost = URLComponents(string: trimmed)?.host,
           !parsedHost.isEmpty {
            return parsedHost
        }

        var candidate = trimmed
        if let schemeRange = candidate.range(of: "://") {
            candidate = String(candidate[schemeRange.upperBound...])
        }

        if let boundary = candidate.firstIndex(where: { character in
            character == "/" || character == "?" || character == "#"
        }) {
            candidate = String(candidate[..<boundary])
        }

        if let colon = candidate.lastIndex(of: ":") {
            let portStart = candidate.index(after: colon)
            let possiblePort = candidate[portStart...]
            if !possiblePort.isEmpty, possiblePort.allSatisfy(\.isNumber) {
                candidate = String(candidate[..<colon])
            }
        }

        return candidate
    }

    private static func matches(_ host: String, root: String) -> Bool {
        host == root || host.hasSuffix(".\(root)")
    }
}
