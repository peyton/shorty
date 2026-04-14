import AppKit
import Combine
import ShortyCore
import SwiftUI

struct StatusBarView: View {
    @StateObject private var snapshotStore: StatusBarSnapshotStore
    @ObservedObject private var translationFeed: TranslationFeed
    private let engine: ShortcutEngine

    init(engine: ShortcutEngine) {
        self.engine = engine
        _snapshotStore = StateObject(
            wrappedValue: StatusBarSnapshotStore(engine: engine)
        )
        self.translationFeed = engine.translationFeed
    }

    var body: some View {
        StatusBarContentView(
            snapshot: snapshotStore.snapshot,
            eventTapEnabled: eventTapEnabledBinding,
            actions: .live(engine: engine),
            recentTranslations: translationFeed.recentEvents,
            dailyStats: translationFeed.dailyStats,
            compactMode: engine.persistedSettings.compactPopoverMode
        )
        .onAppear {
            snapshotStore.refreshFromFrontmostApplication()
        }
    }

    private var eventTapEnabledBinding: Binding<Bool> {
        Binding(
            get: { engine.eventTap.isEnabled },
            set: { engine.eventTap.isEnabled = $0 }
        )
    }
}

final class StatusBarSnapshotStore: ObservableObject {
    @Published private(set) var snapshot: StatusBarSnapshot

    private let engine: ShortcutEngine
    private var cancellables = Set<AnyCancellable>()
    private var refreshScheduled = false

    init(engine: ShortcutEngine) {
        self.engine = engine
        self.snapshot = StatusBarSnapshot.live(engine: engine)
        bind()
    }

    func refreshFromFrontmostApplication() {
        engine.appMonitor.refreshActiveApplication()
        engine.refreshDailyStatuses()
        refresh()
    }

    private func bind() {
        observe(engine.$status) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$permissionState) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$isWaitingForAccessibilityPermission) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$safariExtensionStatus) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$shortcutProfile) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$generatedAdapterPreview) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.$adapterGenerationMessage) { [weak self] _ in
            self?.scheduleRefresh()
        }

        observe(engine.appMonitor.$currentBundleID) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.appMonitor.$currentAppName) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.appMonitor.$webAppDomain) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.appMonitor.$browserContextSource) { [weak self] _ in
            self?.scheduleRefresh()
        }

        observe(engine.registry.$adapters) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.registry.$validationMessages) { [weak self] _ in
            self?.scheduleRefresh()
        }

        observe(engine.eventTap.$isEnabled) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.eventTap.$counters) { [weak self] _ in
            self?.scheduleRefresh()
        }
        observe(engine.eventTap.$lifecycleMessage) { [weak self] _ in
            self?.scheduleRefresh()
        }

        if let browserBridge = engine.browserBridge {
            observe(browserBridge.$status) { [weak self] _ in
                self?.scheduleRefresh()
            }
        }
    }

    private func observe<P: Publisher>(
        _ publisher: P,
        receiveValue: @escaping (P.Output) -> Void
    ) where P.Failure == Never {
        publisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: receiveValue)
            .store(in: &cancellables)
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    private func refresh() {
        snapshot = StatusBarSnapshot.live(engine: engine)
    }
}

struct StatusBarSnapshot {
    let status: EngineDisplayStatus
    let currentAppName: String
    let activeContextTitle: String
    let availability: ShortcutAvailability
    let lifecycleMessage: String?
    let effectiveID: String
    let adapterSource: String
    let mappingCount: String
    let webDomain: String
    let browserContextSource: String
    let bridgeStatus: String
    let safariExtensionStatus: String
    let shortcutReviewCount: Int
    let eventsIntercepted: Int
    let eventsMatched: Int
    let eventsRemapped: Int
    let eventsPassedThrough: Int
    let menuActionsInvoked: Int
    let accessibilityActionsInvoked: Int
    let contextGuardsApplied: Int
    let validationMessages: [String]
    let adapterGenerationMessage: String?
    let hasGeneratedAdapterPreview: Bool

    var requiresPermission: Bool {
        status.requiresPermission
    }

    var statusTitle: String {
        status.title
    }

    var statusDetail: String {
        status.detail
    }

    var statusIsHealthy: Bool {
        status.isHealthy
    }

    static func live(engine: ShortcutEngine) -> StatusBarSnapshot {
        let appSnapshot = engine.appMonitor.snapshot()
        let appID = appSnapshot.effectiveAppID
        let activeTitle = activeContextTitle(
            engine: engine,
            appSnapshot: appSnapshot
        )
        let availability = engine.registry.availability(
            for: appID,
            displayName: activeTitle
        )

        let normalizedWebDomain: String
        if let domain = appSnapshot.webAppDomain {
            normalizedWebDomain = DomainNormalizer.normalizedDomain(for: domain)
        } else {
            normalizedWebDomain = "None"
        }

        return StatusBarSnapshot(
            status: EngineDisplayStatus.make(
                status: engine.status,
                permissionState: engine.permissionState,
                eventTapEnabled: engine.eventTap.isEnabled,
                isWaitingForPermission: engine.isWaitingForAccessibilityPermission
            ),
            currentAppName: appSnapshot.currentAppName ?? "Unknown",
            activeContextTitle: activeTitle,
            availability: availability,
            lifecycleMessage: importantLifecycleMessage(engine: engine),
            effectiveID: appID ?? "None",
            adapterSource: availability.adapterSource?.statusLabel ?? "none",
            mappingCount: "\(availability.shortcuts.count)",
            webDomain: normalizedWebDomain,
            browserContextSource: appSnapshot.browserContextSource.title,
            bridgeStatus: engine.browserBridge?.status.title ?? "Unavailable",
            safariExtensionStatus: engine.safariExtensionStatus.title,
            shortcutReviewCount: engine.shortcutProfile.conflicts().count,
            eventsIntercepted: engine.eventTap.eventsIntercepted,
            eventsMatched: engine.eventTap.shortcutsMatched,
            eventsRemapped: engine.eventTap.eventsRemapped,
            eventsPassedThrough: engine.eventTap.counters.eventsPassedThrough,
            menuActionsInvoked: engine.eventTap.counters.menuActionsInvoked,
            accessibilityActionsInvoked: engine.eventTap.counters.accessibilityActionsInvoked,
            contextGuardsApplied: engine.eventTap.counters.contextGuardsApplied,
            validationMessages: engine.registry.validationMessages,
            adapterGenerationMessage: engine.adapterGenerationMessage,
            hasGeneratedAdapterPreview: engine.generatedAdapterPreview != nil
        )
    }

    private static func activeContextTitle(
        engine: ShortcutEngine,
        appSnapshot: AppMonitor.Snapshot
    ) -> String {
        let appName = appSnapshot.currentAppName ?? "Unknown"
        guard let domain = appSnapshot.webAppDomain,
              let appID = appSnapshot.effectiveAppID,
              appID.hasPrefix("web:")
        else {
            return appName
        }

        let adapterName = engine.registry.activeAdapter(for: appID)?.appName
            ?? DomainNormalizer.normalizedDomain(for: domain)
        return "\(adapterName) in \(appName)"
    }

    private static func importantLifecycleMessage(engine: ShortcutEngine) -> String? {
        guard engine.eventTap.isEnabled else { return nil }
        return engine.eventTap.lifecycleMessage
    }
}

struct StatusBarActions {
    let openAccessibilitySettings: () -> Void
    let addCurrentApp: () -> Void
    let openSettings: () -> Void
    let pauseCurrentApp: () -> Void
    let resumeCurrentApp: () -> Void
    let pauseFor15Minutes: () -> Void
    let quit: () -> Void

    static let noop = StatusBarActions(
        openAccessibilitySettings: {},
        addCurrentApp: {},
        openSettings: {},
        pauseCurrentApp: {},
        resumeCurrentApp: {},
        pauseFor15Minutes: {},
        quit: {}
    )

    static func live(engine: ShortcutEngine) -> StatusBarActions {
        StatusBarActions(
            openAccessibilitySettings: { engine.openAccessibilitySettings() },
            addCurrentApp: {
                engine.generateAdapterForCurrentApp()
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            openSettings: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            },
            pauseCurrentApp: { engine.pauseCurrentApp() },
            resumeCurrentApp: { engine.resumeCurrentApp() },
            pauseFor15Minutes: { engine.pauseForDuration(15 * 60) },
            quit: {
                engine.stop()
                NSApp.terminate(nil)
            }
        )
    }
}

struct StatusBarContentView: View {
    let snapshot: StatusBarSnapshot
    let eventTapEnabled: Binding<Bool>
    let actions: StatusBarActions
    var recentTranslations: [TranslationEvent]
    var dailyStats: DailyUsageStats
    var compactMode: Bool

    @State private var showsDetails: Bool
    @State private var popoverSearch = ""
    @State private var showLiveFeed = false
    @FocusState private var searchFocused: Bool

    init(
        snapshot: StatusBarSnapshot,
        eventTapEnabled: Binding<Bool>,
        actions: StatusBarActions = .noop,
        showsDetails: Bool = false,
        recentTranslations: [TranslationEvent] = [],
        dailyStats: DailyUsageStats = DailyUsageStats(),
        compactMode: Bool = false
    ) {
        self.snapshot = snapshot
        self.eventTapEnabled = eventTapEnabled
        self.actions = actions
        self.recentTranslations = recentTranslations
        self.dailyStats = dailyStats
        self.compactMode = compactMode
        _showsDetails = State(initialValue: showsDetails)
    }

    var contentPresentation: StatusBarContentPresentation {
        StatusBarContentPresentation(snapshot: snapshot)
    }

    var body: some View {
        let presentation = contentPresentation

        VStack(alignment: .leading, spacing: 14) {
            StatusHeader(snapshot: snapshot)

            // Bridge/web indicator (#33, #35)
            if snapshot.webDomain != "None", snapshot.bridgeStatus != "Unavailable" {
                BridgeIndicatorBanner(
                    webDomain: snapshot.webDomain,
                    bridgeStatus: snapshot.bridgeStatus
                )
            }

            PermissionBanner(snapshot: snapshot, actions: actions)

            if !compactMode {
                // Popover search (#8)
                PopoverSearchField(searchText: $popoverSearch)
                    .focused($searchFocused)

                // Live feed toggle + available shortcuts (#6, #9)
                Picker("View", selection: $showLiveFeed) {
                    Text("Available").tag(false)
                    Text("Activity").tag(true)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()

                if showLiveFeed {
                    LiveFeedView(
                        events: recentTranslations,
                        canonicalShortcuts: []
                    )
                } else {
                    AvailableShortcutsSection(
                        presentation: filteredPresentation(presentation.shortcuts),
                        actions: actions
                    )
                }
            }

            TranslationControlSection(
                snapshot: snapshot,
                eventTapEnabled: eventTapEnabled
            )

            // Usage summary footer (#22)
            if dailyStats.totalTranslations > 0 {
                UsageSummaryRow(stats: dailyStats)
            }

            DetailsSection(snapshot: snapshot, showsDetails: $showsDetails)
            StatusFooter(actions: actions)
        }
        .padding(16)
        .frame(width: 430)
        .accessibilityIdentifier("status-popover")
    }

    private func filteredPresentation(
        _ original: StatusBarShortcutsPresentation
    ) -> StatusBarShortcutsPresentation {
        guard !popoverSearch.isEmpty else { return original }
        let query = popoverSearch.lowercased()
        let filtered = original.rows.filter {
            $0.name.lowercased().contains(query)
                || $0.defaultKeys.lowercased().contains(query)
                || $0.actionDescription.lowercased().contains(query)
        }
        return StatusBarShortcutsPresentation(
            title: original.title,
            coverageDetail: original.coverageDetail,
            rows: filtered,
            emptyState: filtered.isEmpty
                ? EmptyShortcutStatePresentation(
                    title: "No matches",
                    detail: "No shortcuts match \"\(popoverSearch)\".",
                    showsAddButton: false
                )
                : nil,
            showsPauseActions: original.showsPauseActions && filtered.count == original.rows.count,
            showsResumeAction: original.showsResumeAction,
            adapterGenerationMessage: original.adapterGenerationMessage,
            hasGeneratedAdapterPreview: original.hasGeneratedAdapterPreview
        )
    }
}

/// Bridge connection indicator shown when a web adapter is active (#33, #35).
private struct BridgeIndicatorBanner: View {
    let webDomain: String
    let bridgeStatus: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundColor(ShortyBrand.teal)
                .font(.caption)
            Text(webDomain)
                .font(.caption.weight(.medium))
            Spacer()
            Text(bridgeStatus)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ShortyBrand.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Web app: \(webDomain), \(bridgeStatus)")
    }
}

/// Usage summary row for the popover footer (#22).
private struct UsageSummaryRow: View {
    let stats: DailyUsageStats

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(ShortyBrand.teal)
                .font(.caption2)
            Text(stats.summaryText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .accessibilityLabel(stats.summaryText)
    }
}

struct StatusBarContentPresentation: Equatable {
    let statusTitle: String
    let activeContextTitle: String
    let shortcuts: StatusBarShortcutsPresentation

    init(snapshot: StatusBarSnapshot) {
        self.statusTitle = snapshot.status.title
        self.activeContextTitle = snapshot.activeContextTitle
        self.shortcuts = StatusBarShortcutsPresentation(snapshot: snapshot)
    }
}

private struct StatusHeader: View {
    let snapshot: StatusBarSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ShortyMenuBarGlyph(status: engineStatusForGlyph)
                .accessibilityLabel(snapshot.status.title)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(snapshot.status.title)
                        .font(.headline)
                    CoverageBadge(availability: snapshot.availability)
                }
                Text(snapshot.activeContextTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(snapshot.status.title), \(snapshot.activeContextTitle)")
    }

    private var engineStatusForGlyph: EngineStatus {
        if snapshot.requiresPermission {
            return .permissionRequired
        }
        if snapshot.status.title == "Paused" {
            return .disabled
        }
        return snapshot.status.isHealthy ? .running : .failed(snapshot.status.detail)
    }
}

private struct CoverageBadge: View {
    let availability: ShortcutAvailability

    var body: some View {
        Text(availability.coverageTitle)
            .font(.caption.weight(.semibold))
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel("Coverage: \(availability.coverageTitle)")
    }

    private var foregroundColor: Color {
        switch availability.state {
        case .available:
            return ShortyBrand.teal
        case .paused:
            return ShortyBrand.amber
        case .noActiveApp, .noAdapter:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch availability.state {
        case .available:
            return ShortyBrand.teal.opacity(0.12)
        case .paused:
            return ShortyBrand.amber.opacity(0.12)
        case .noActiveApp, .noAdapter:
            return Color.secondary.opacity(0.12)
        }
    }
}

private struct PermissionBanner: View {
    let snapshot: StatusBarSnapshot
    let actions: StatusBarActions

    var body: some View {
        if snapshot.requiresPermission {
            ShortyPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.status.title)
                                .font(.callout.weight(.semibold))
                            Text(snapshot.status.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "accessibility")
                            .foregroundColor(ShortyBrand.amber)
                    }

                    HStack(spacing: 10) {
                        Button(
                            "Open Accessibility Settings",
                            action: actions.openAccessibilitySettings
                        )
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        if snapshot.status.isWaitingForPermission {
                            ProgressView()
                                .controlSize(.small)
                            Text("Watching for approval")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(snapshot.status.title)
        }
    }
}

struct StatusBarShortcutsPresentation: Equatable {
    let title: String
    let coverageDetail: String
    let rows: [ShortcutRowPresentation]
    let emptyState: EmptyShortcutStatePresentation?
    let showsPauseActions: Bool
    let showsResumeAction: Bool
    let adapterGenerationMessage: String?
    let hasGeneratedAdapterPreview: Bool

    init(
        title: String,
        coverageDetail: String,
        rows: [ShortcutRowPresentation],
        emptyState: EmptyShortcutStatePresentation?,
        showsPauseActions: Bool,
        showsResumeAction: Bool,
        adapterGenerationMessage: String?,
        hasGeneratedAdapterPreview: Bool
    ) {
        self.title = title
        self.coverageDetail = coverageDetail
        self.rows = rows
        self.emptyState = emptyState
        self.showsPauseActions = showsPauseActions
        self.showsResumeAction = showsResumeAction
        self.adapterGenerationMessage = adapterGenerationMessage
        self.hasGeneratedAdapterPreview = hasGeneratedAdapterPreview
    }

    init(snapshot: StatusBarSnapshot) {
        self.title = "Available now"
        self.coverageDetail = snapshot.availability.coverageDetail
        self.adapterGenerationMessage = snapshot.adapterGenerationMessage
        self.hasGeneratedAdapterPreview = snapshot.hasGeneratedAdapterPreview

        switch snapshot.availability.state {
        case .available:
            self.rows = snapshot.availability.shortcuts.map(ShortcutRowPresentation.init)
            self.emptyState = nil
            self.showsPauseActions = true
            self.showsResumeAction = false
        case .paused:
            self.rows = []
            self.emptyState = EmptyShortcutStatePresentation(
                title: "Paused for this app",
                detail: "Shorty is passing keys through for this app.",
                showsAddButton: false
            )
            self.showsPauseActions = false
            self.showsResumeAction = true
        case .noActiveApp:
            self.rows = []
            self.emptyState = EmptyShortcutStatePresentation(
                title: "No app selected",
                detail: "Click into an app and Shorty will show its shortcuts here.",
                showsAddButton: false
            )
            self.showsPauseActions = false
            self.showsResumeAction = false
        case .noAdapter:
            self.rows = []
            self.emptyState = EmptyShortcutStatePresentation(
                title: "No shortcuts for this app yet",
                detail: "Shorty will pass keys through until you add support for this app.",
                showsAddButton: !snapshot.requiresPermission
            )
            self.showsPauseActions = false
            self.showsResumeAction = false
        }
    }
}

struct ShortcutRowPresentation: Equatable, Identifiable {
    let id: String
    let name: String
    let defaultKeys: String
    let actionDescription: String
    let actionKind: AvailableShortcutActionKind

    init(shortcut: AvailableShortcut) {
        self.id = shortcut.id
        self.name = shortcut.name
        self.defaultKeys = shortcut.defaultKeys.displayString
        self.actionDescription = shortcut.actionDescription
        self.actionKind = shortcut.actionKind
    }
}

struct EmptyShortcutStatePresentation: Equatable {
    let title: String
    let detail: String
    let showsAddButton: Bool
}

private struct AvailableShortcutsSection: View {
    let presentation: StatusBarShortcutsPresentation
    let actions: StatusBarActions

    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presentation.title)
                            .font(.callout.weight(.semibold))
                        Text(presentation.coverageDetail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                if !presentation.rows.isEmpty {
                    ShortcutList(shortcuts: presentation.rows)
                }

                if presentation.showsPauseActions {
                    HStack(spacing: 8) {
                        Button("Pause This App", action: actions.pauseCurrentApp)
                        Button("Pause 15 Min", action: actions.pauseFor15Minutes)
                    }
                    .controlSize(.small)
                }

                if let emptyState = presentation.emptyState {
                    EmptyShortcutState(presentation: emptyState, actions: actions)
                }

                if presentation.showsResumeAction {
                    Button("Resume This App", action: actions.resumeCurrentApp)
                        .controlSize(.small)
                }

                if let message = presentation.adapterGenerationMessage {
                    AdapterGenerationMessage(
                        message: message,
                        hasPreview: presentation.hasGeneratedAdapterPreview
                    )
                }
            }
        }
    }
}

private struct ShortcutList: View {
    let shortcuts: [ShortcutRowPresentation]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(shortcuts) { shortcut in
                    AvailableShortcutRow(shortcut: shortcut)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxHeight: 260)
    }
}

private struct AvailableShortcutRow: View {
    let shortcut: ShortcutRowPresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ShortcutKeyBadge(text: shortcut.defaultKeys)
                .frame(minWidth: 58, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(shortcut.actionDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            ShortcutActionPill(kind: shortcut.actionKind)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(shortcut.name), \(shortcut.defaultKeys), \(shortcut.actionDescription)"
        )
    }
}

private struct ShortcutActionPill: View {
    let kind: AvailableShortcutActionKind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

private struct EmptyShortcutState: View {
    let presentation: EmptyShortcutStatePresentation
    let actions: StatusBarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(presentation.title, systemImage: "keyboard.badge.ellipsis")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(presentation.detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if presentation.showsAddButton {
                Button("Add Current App", action: actions.addCurrentApp)
                    .controlSize(.small)
            }
        }
    }
}

private struct AdapterGenerationMessage: View {
    let message: String
    let hasPreview: Bool

    var body: some View {
        Label(
            hasPreview ? "\(message) Open Apps settings to review it." : message,
            systemImage: hasPreview ? "checkmark.circle" : "info.circle"
        )
        .font(.caption)
        .foregroundColor(hasPreview ? ShortyBrand.teal : .secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TranslationControlSection: View {
    let snapshot: StatusBarSnapshot
    let eventTapEnabled: Binding<Bool>

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcut translation")
                    .font(.caption.weight(.semibold))
                Text(controlDetail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("Shortcut translation", isOn: eventTapEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(snapshot.requiresPermission)
                .accessibilityLabel("Shortcut translation")
        }
    }

    private var controlDetail: String {
        if snapshot.requiresPermission {
            return "Blocked until Accessibility access is granted."
        }
        if eventTapEnabled.wrappedValue {
            return "Ready for supported apps."
        }
        return "Paused by you."
    }
}

private struct DetailsSection: View {
    let snapshot: StatusBarSnapshot
    @Binding var showsDetails: Bool

    var body: some View {
        DisclosureGroup("Details", isExpanded: $showsDetails) {
            VStack(alignment: .leading, spacing: 8) {
                if let lifecycleMessage = snapshot.lifecycleMessage {
                    Label(lifecycleMessage, systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                StatusInfoRow("Effective app", snapshot.effectiveID)
                StatusInfoRow("Adapter", snapshot.adapterSource)
                StatusInfoRow("Mappings", snapshot.mappingCount)
                StatusInfoRow("Web domain", snapshot.webDomain)
                StatusInfoRow("Browser source", snapshot.browserContextSource)
                StatusInfoRow("Bridge", snapshot.bridgeStatus)
                StatusInfoRow("Safari", snapshot.safariExtensionStatus)
                StatusInfoRow("Shortcut review", "\(snapshot.shortcutReviewCount)")
                StatusInfoRow("Key events seen", "\(snapshot.eventsIntercepted)")
                StatusInfoRow("Shortcuts matched", "\(snapshot.eventsMatched)")
                StatusInfoRow("Key remaps", "\(snapshot.eventsRemapped)")
                StatusInfoRow("Native pass-throughs", "\(snapshot.eventsPassedThrough)")
                StatusInfoRow("Menu actions", "\(snapshot.menuActionsInvoked)")
                StatusInfoRow("Accessibility actions", "\(snapshot.accessibilityActionsInvoked)")
                StatusInfoRow("Context guards", "\(snapshot.contextGuardsApplied)")

                if !snapshot.validationMessages.isEmpty {
                    Label(
                        "\(snapshot.validationMessages.count) adapter warning\(snapshot.validationMessages.count == 1 ? "" : "s")",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundColor(ShortyBrand.amber)
                }
            }
            .padding(.top, 6)
        }
        .font(.caption)
    }
}

private struct StatusFooter: View {
    let actions: StatusBarActions

    var body: some View {
        HStack {
            Button("Settings...", action: actions.openSettings)
                .accessibilityIdentifier("status-settings")

            Spacer()

            Button("Quit", action: actions.quit)
                .accessibilityIdentifier("status-quit")
        }
    }
}

private struct StatusInfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }
}

private extension Adapter.Source {
    var statusLabel: String {
        switch self {
        case .builtin:
            return "Built-in"
        case .menuIntrospection:
            return "Generated"
        case .llmGenerated:
            return "Generated"
        case .community:
            return "Community"
        case .user:
            return "User"
        }
    }
}
