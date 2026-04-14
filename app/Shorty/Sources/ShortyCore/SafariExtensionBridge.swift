import Foundation

public enum SafariExtensionBridge {
    public static let appGroupSuiteName = "group.app.peyton.shorty"
    public static let lastMessageDefaultsKey = "Shorty.SafariExtension.LastMessage"
    public static let notificationName = Notification.Name(
        "app.peyton.shorty.safariExtensionMessage"
    )

    public static func readLastMessage(
        userDefaults: UserDefaults? = UserDefaults(suiteName: appGroupSuiteName)
    ) -> SafariExtensionBridgeMessage? {
        guard let data = userDefaults?.data(forKey: lastMessageDefaultsKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SafariExtensionBridgeMessage.self, from: data)
    }
}

public struct SafariExtensionBridgeMessage: Codable, Equatable {
    public enum Kind: String, Codable {
        case domainChanged
        case domainCleared
    }

    public let kind: Kind
    public let domain: String?
    public let createdAt: Date

    public init(
        kind: Kind,
        domain: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.domain = domain
        self.createdAt = createdAt
    }
}
