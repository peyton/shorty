import AppKit
import Foundation

/// Result of scanning installed applications for adapter coverage.
public struct AppScanResult: Identifiable, Equatable {
    public let id: String
    public let bundleIdentifier: String
    public let appName: String
    public let appIcon: NSImage?
    public let coverageState: CoverageState

    public enum CoverageState: Equatable {
        case builtIn(mappingCount: Int)
        case generated(mappingCount: Int)
        case userDefined(mappingCount: Int)
        case uncovered
    }

    public var hasCoverage: Bool {
        switch coverageState {
        case .builtIn, .generated, .userDefined:
            return true
        case .uncovered:
            return false
        }
    }

    public var mappingCount: Int {
        switch coverageState {
        case .builtIn(let count), .generated(let count), .userDefined(let count):
            return count
        case .uncovered:
            return 0
        }
    }

    public var sourceLabel: String {
        switch coverageState {
        case .builtIn:
            return "Built-in"
        case .generated:
            return "Generated"
        case .userDefined:
            return "User"
        case .uncovered:
            return "None"
        }
    }
}

/// Scans installed applications and checks adapter coverage.
public enum AppScanner {
    /// Scan standard application directories and return coverage results.
    public static func scan(registry: AdapterRegistry) -> [AppScanResult] {
        let searchDirs = applicationDirectories()
        var results: [AppScanResult] = []
        var seenBundleIDs = Set<String>()

        for dir in searchDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seenBundleIDs.contains(bundleID)
                else { continue }

                seenBundleIDs.insert(bundleID)

                let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? url.deletingPathExtension().lastPathComponent

                // Skip system daemons, agents, and helper apps
                guard !isSystemDaemon(bundleID: bundleID, appName: appName) else { continue }

                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let coverageState = adapterCoverage(
                    for: bundleID,
                    registry: registry
                )

                results.append(AppScanResult(
                    id: bundleID,
                    bundleIdentifier: bundleID,
                    appName: appName,
                    appIcon: icon,
                    coverageState: coverageState
                ))
            }
        }

        return results.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }

    /// Summary of scan results for display.
    public static func scanSummary(results: [AppScanResult]) -> ScanSummary {
        let covered = results.filter(\.hasCoverage)
        let uncovered = results.filter { !$0.hasCoverage }
        return ScanSummary(
            totalApps: results.count,
            coveredApps: covered.count,
            uncoveredApps: uncovered.count,
            builtInCount: results.filter { if case .builtIn = $0.coverageState { return true }; return false }.count,
            generatedCount: results.filter { if case .generated = $0.coverageState { return true }; return false }.count,
            userDefinedCount: results.filter { if case .userDefined = $0.coverageState { return true }; return false }.count
        )
    }

    private static func applicationDirectories() -> [URL] {
        var dirs: [URL] = []
        dirs.append(URL(fileURLWithPath: "/Applications", isDirectory: true))
        if let home = FileManager.default.homeDirectoryForCurrentUser as URL? {
            dirs.append(home.appendingPathComponent("Applications", isDirectory: true))
        }
        dirs.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
        return dirs
    }

    private static func adapterCoverage(
        for bundleID: String,
        registry: AdapterRegistry
    ) -> AppScanResult.CoverageState {
        guard let adapter = registry.activeAdapter(for: bundleID) else {
            return .uncovered
        }
        let count = adapter.mappings.count
        switch adapter.source {
        case .builtin:
            return .builtIn(mappingCount: count)
        case .menuIntrospection, .llmGenerated:
            return .generated(mappingCount: count)
        case .community, .user:
            return .userDefined(mappingCount: count)
        }
    }

    private static func isSystemDaemon(bundleID: String, appName: String) -> Bool {
        let prefixes = [
            "com.apple.dt.", "com.apple.security.", "com.apple.accessibility.",
            "com.apple.preference.", "com.apple.print.", "com.apple.systempreferences."
        ]
        for prefix in prefixes where bundleID.hasPrefix(prefix) {
            return true
        }
        let names = ["Setup Assistant", "Installer", "Migration Assistant", "Bluetooth Setup Assistant"]
        return names.contains(appName)
    }
}

// MARK: - Scan Summary

public struct ScanSummary: Equatable {
    public let totalApps: Int
    public let coveredApps: Int
    public let uncoveredApps: Int
    public let builtInCount: Int
    public let generatedCount: Int
    public let userDefinedCount: Int

    public var coveragePercentage: Int {
        guard totalApps > 0 else { return 0 }
        return (coveredApps * 100) / totalApps
    }

    public var summaryText: String {
        "\(coveredApps) of \(totalApps) apps have keyboard shortcuts (\(coveragePercentage)% coverage)."
    }
}
