import Foundation

/// Read-only inspector for Chrome-family native messaging manifests.
///
/// Installation needs a browser extension ID and a built helper executable, so
/// the app should not guess or silently write files. This manager makes the
/// current state visible in Settings and support bundles.
public struct BrowserBridgeInstallManager {
    public static let nativeHostName = "com.shorty.browser_bridge"

    private let fileManager: FileManager
    private let homeDirectory: URL

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    public func statuses(
        for browsers: [BridgeBrowserTarget] = BridgeBrowserTarget.allCases
    ) -> [BridgeInstallStatus] {
        browsers.map(status(for:))
    }

    public func status(for browser: BridgeBrowserTarget) -> BridgeInstallStatus {
        guard let manifestURL = manifestURL(for: browser) else {
            return BridgeInstallStatus(
                browser: browser,
                state: .unsupported,
                detail: "\(browser.displayName) does not use the Chrome-family native messaging bridge."
            )
        }

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return BridgeInstallStatus(
                browser: browser,
                state: .notInstalled,
                manifestPath: manifestURL.path,
                detail: "No Shorty native messaging manifest is installed for \(browser.displayName)."
            )
        }

        guard let payload = readManifest(at: manifestURL) else {
            return BridgeInstallStatus(
                browser: browser,
                state: .needsAttention,
                manifestPath: manifestURL.path,
                detail: "The Shorty manifest exists but could not be read."
            )
        }

        let helperPath = payload["path"] as? String
        guard payload["name"] as? String == Self.nativeHostName else {
            return BridgeInstallStatus(
                browser: browser,
                state: .needsAttention,
                manifestPath: manifestURL.path,
                helperPath: helperPath,
                detail: "The manifest name does not match Shorty's native host."
            )
        }

        guard let helperPath, !helperPath.isEmpty else {
            return BridgeInstallStatus(
                browser: browser,
                state: .needsAttention,
                manifestPath: manifestURL.path,
                detail: "The manifest is missing the Shorty bridge executable path."
            )
        }

        guard fileManager.isExecutableFile(atPath: helperPath) else {
            return BridgeInstallStatus(
                browser: browser,
                state: .needsAttention,
                manifestPath: manifestURL.path,
                helperPath: helperPath,
                detail: "The manifest points to a bridge helper that is missing or not executable."
            )
        }

        return BridgeInstallStatus(
            browser: browser,
            state: .installed,
            manifestPath: manifestURL.path,
            helperPath: helperPath,
            detail: "\(browser.displayName) can reach Shorty's browser bridge helper."
        )
    }

    private func manifestURL(for browser: BridgeBrowserTarget) -> URL? {
        guard let relativePath = Self.manifestRelativePath(for: browser) else {
            return nil
        }
        return homeDirectory.appendingPathComponent(relativePath, isDirectory: false)
    }

    private static func manifestRelativePath(for browser: BridgeBrowserTarget) -> String? {
        let directory: String
        switch browser {
        case .chrome:
            directory = "Library/Application Support/Google/Chrome/NativeMessagingHosts"
        case .chromeCanary:
            directory = "Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"
        case .chromium:
            directory = "Library/Application Support/Chromium/NativeMessagingHosts"
        case .brave:
            directory = "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
        case .edge:
            directory = "Library/Application Support/Microsoft Edge/NativeMessagingHosts"
        case .vivaldi:
            directory = "Library/Application Support/Vivaldi/NativeMessagingHosts"
        case .safari:
            return nil
        }
        return "\(directory)/\(nativeHostName).json"
    }

    private func readManifest(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any]
        else {
            return nil
        }
        return payload
    }
}
