import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let appGroupSuiteName = "group.app.peyton.shorty"
    private let lastMessageDefaultsKey = "Shorty.SafariExtension.LastMessage"
    private let notificationName = Notification.Name(
        "app.peyton.shorty.safariExtensionMessage"
    )

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]

        let responsePayload = handle(message: message)
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: responsePayload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }

    private func handle(message: Any?) -> [String: Any] {
        guard let payload = message as? [String: Any],
              let type = payload["type"] as? String
        else {
            return ["type": "error", "message": "Invalid Shorty Safari message."]
        }

        switch type {
        case "domain_changed":
            guard let domain = payload["domain"] as? String, !domain.isEmpty else {
                return ["type": "error", "message": "Missing domain."]
            }
            persist(kind: "domainChanged", domain: domain)
            return ["type": "ack"]
        case "domain_cleared":
            persist(kind: "domainCleared", domain: nil)
            return ["type": "ack"]
        default:
            return ["type": "error", "message": "Unknown message type."]
        }
    }

    private func persist(kind: String, domain: String?) {
        var payload: [String: Any] = [
            "kind": kind,
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let domain {
            payload["domain"] = domain
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        ) else { return }

        let defaults = UserDefaults(suiteName: appGroupSuiteName)
        defaults?.set(data, forKey: lastMessageDefaultsKey)
        defaults?.synchronize()

        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
