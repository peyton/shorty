import Combine
import Foundation

/// A single shortcut translation that occurred at a point in time.
public struct TranslationEvent: Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let canonicalID: String
    public let canonicalName: String
    public let inputKeys: KeyCombo
    public let appName: String
    public let appIdentifier: String
    public let actionKind: AvailableShortcutActionKind
    public let actionDescription: String
    public let succeeded: Bool?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        canonicalID: String,
        canonicalName: String,
        inputKeys: KeyCombo,
        appName: String,
        appIdentifier: String,
        actionKind: AvailableShortcutActionKind,
        actionDescription: String,
        succeeded: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.canonicalID = canonicalID
        self.canonicalName = canonicalName
        self.inputKeys = inputKeys
        self.appName = appName
        self.appIdentifier = appIdentifier
        self.actionKind = actionKind
        self.actionDescription = actionDescription
        self.succeeded = succeeded
    }
}

/// Records a rolling window of translation events for live UI display and usage stats.
///
/// The feed is thread-safe: events are posted from the event-tap thread and
/// consumed on the main thread. A fixed-size ring buffer keeps memory bounded.
public final class TranslationFeed: ObservableObject {
    public static let maxEvents = 50
    public static let dailyStatsDefaultsKey = "Shorty.TranslationFeed.DailyStats"

    @Published public private(set) var recentEvents: [TranslationEvent] = []
    @Published public private(set) var dailyStats: DailyUsageStats

    private let lock = NSLock()
    private var pendingEvents: [TranslationEvent] = []
    private var pendingFailures: [TranslationEvent] = []
    private let userDefaults: UserDefaults
    private var flushScheduled = false

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.dailyStats = Self.loadDailyStats(userDefaults: userDefaults)
    }

    /// Post a translation event from any thread (typically the event-tap thread).
    public func post(_ event: TranslationEvent) {
        lock.lock()
        pendingEvents.append(event)
        lock.unlock()
        scheduleFlush()
    }

    /// Post an async action result (success/failure) for a previously posted event.
    public func postFailure(_ event: TranslationEvent) {
        lock.lock()
        pendingFailures.append(event)
        lock.unlock()
        scheduleFlush()
    }

    /// Drain pending events onto the main thread.
    public func flush() {
        lock.lock()
        let events = pendingEvents
        let failures = pendingFailures
        pendingEvents.removeAll()
        pendingFailures.removeAll()
        lock.unlock()

        guard !events.isEmpty || !failures.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var recent = self.recentEvents

            for event in events {
                recent.append(event)
                self.dailyStats.record(event)
            }

            for failure in failures {
                if let index = recent.lastIndex(where: { $0.canonicalID == failure.canonicalID && $0.appIdentifier == failure.appIdentifier }) {
                    recent[index] = failure
                }
                self.dailyStats.recordFailure()
            }

            if recent.count > Self.maxEvents {
                recent = Array(recent.suffix(Self.maxEvents))
            }

            self.recentEvents = recent
            self.persistDailyStats()
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.flush()
        }
    }

    private func persistDailyStats() {
        guard let data = try? JSONEncoder().encode(dailyStats) else { return }
        userDefaults.set(data, forKey: Self.dailyStatsDefaultsKey)
    }

    private static func loadDailyStats(userDefaults: UserDefaults) -> DailyUsageStats {
        guard let data = userDefaults.data(forKey: dailyStatsDefaultsKey),
              let stats = try? JSONDecoder().decode(DailyUsageStats.self, from: data),
              Calendar.current.isDateInToday(stats.date)
        else {
            return DailyUsageStats()
        }
        return stats
    }
}

// MARK: - Daily Usage Stats

public struct DailyUsageStats: Codable, Equatable {
    public let date: Date
    public private(set) var totalTranslations: Int
    public private(set) var uniqueApps: Set<String>
    public private(set) var shortcutCounts: [String: Int]
    public private(set) var failures: Int

    public init(
        date: Date = Date(),
        totalTranslations: Int = 0,
        uniqueApps: Set<String> = [],
        shortcutCounts: [String: Int] = [:],
        failures: Int = 0
    ) {
        self.date = date
        self.totalTranslations = totalTranslations
        self.uniqueApps = uniqueApps
        self.shortcutCounts = shortcutCounts
        self.failures = failures
    }

    public mutating func record(_ event: TranslationEvent) {
        totalTranslations += 1
        uniqueApps.insert(event.appIdentifier)
        shortcutCounts[event.canonicalID, default: 0] += 1
    }

    public mutating func recordFailure() {
        failures += 1
    }

    public var topShortcut: (id: String, count: Int)? {
        shortcutCounts.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    public var summaryText: String {
        if totalTranslations == 0 {
            return "No shortcuts translated yet today."
        }
        let appCount = uniqueApps.count
        return "Today: \(totalTranslations) shortcut\(totalTranslations == 1 ? "" : "s") translated across \(appCount) app\(appCount == 1 ? "" : "s")."
    }
}

// MARK: - Weekly Stats (for digest notifications)

public struct WeeklyUsageStats: Codable, Equatable {
    public static let defaultsKey = "Shorty.TranslationFeed.WeeklyStats"

    public let weekStart: Date
    public private(set) var totalTranslations: Int
    public private(set) var shortcutCounts: [String: Int]
    public private(set) var uniqueApps: Set<String>
    public private(set) var daysActive: Int

    public init(weekStart: Date = Date()) {
        self.weekStart = weekStart
        self.totalTranslations = 0
        self.shortcutCounts = [:]
        self.uniqueApps = []
        self.daysActive = 0
    }

    public mutating func mergeDaily(_ daily: DailyUsageStats) {
        totalTranslations += daily.totalTranslations
        uniqueApps.formUnion(daily.uniqueApps)
        for (id, count) in daily.shortcutCounts {
            shortcutCounts[id, default: 0] += count
        }
        if daily.totalTranslations > 0 {
            daysActive += 1
        }
    }

    public var topShortcuts: [(id: String, count: Int)] {
        shortcutCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }
    }
}
