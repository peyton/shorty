import AppKit
import Combine
import CoreGraphics
import OSLog

public struct EventTapCounters: Codable, Equatable {
    public private(set) var keyDownEventsSeen: Int
    public private(set) var shortcutsMatched: Int
    public private(set) var eventsRemapped: Int
    public private(set) var eventsPassedThrough: Int
    public private(set) var menuActionsInvoked: Int
    public private(set) var menuActionsSucceeded: Int
    public private(set) var menuActionsFailed: Int
    public private(set) var accessibilityActionsInvoked: Int
    public private(set) var accessibilityActionsSucceeded: Int
    public private(set) var accessibilityActionsFailed: Int
    public private(set) var contextGuardsApplied: Int

    public init(
        keyDownEventsSeen: Int = 0,
        shortcutsMatched: Int = 0,
        eventsRemapped: Int = 0,
        eventsPassedThrough: Int = 0,
        menuActionsInvoked: Int = 0,
        menuActionsSucceeded: Int = 0,
        menuActionsFailed: Int = 0,
        accessibilityActionsInvoked: Int = 0,
        accessibilityActionsSucceeded: Int = 0,
        accessibilityActionsFailed: Int = 0,
        contextGuardsApplied: Int = 0
    ) {
        self.keyDownEventsSeen = keyDownEventsSeen
        self.shortcutsMatched = shortcutsMatched
        self.eventsRemapped = eventsRemapped
        self.eventsPassedThrough = eventsPassedThrough
        self.menuActionsInvoked = menuActionsInvoked
        self.menuActionsSucceeded = menuActionsSucceeded
        self.menuActionsFailed = menuActionsFailed
        self.accessibilityActionsInvoked = accessibilityActionsInvoked
        self.accessibilityActionsSucceeded = accessibilityActionsSucceeded
        self.accessibilityActionsFailed = accessibilityActionsFailed
        self.contextGuardsApplied = contextGuardsApplied
    }

    public var isEmpty: Bool {
        keyDownEventsSeen == 0
            && shortcutsMatched == 0
            && eventsRemapped == 0
            && eventsPassedThrough == 0
            && menuActionsInvoked == 0
            && menuActionsSucceeded == 0
            && menuActionsFailed == 0
            && accessibilityActionsInvoked == 0
            && accessibilityActionsSucceeded == 0
            && accessibilityActionsFailed == 0
            && contextGuardsApplied == 0
    }

    public mutating func recordKeyDownEvent() {
        keyDownEventsSeen += 1
    }

    public mutating func recordResolvedAction(_ action: AdapterRegistry.ResolvedAction) {
        shortcutsMatched += 1
        switch action {
        case .remap:
            eventsRemapped += 1
        case .passthrough:
            eventsPassedThrough += 1
        case .invokeMenu:
            menuActionsInvoked += 1
        case .performAXAction:
            accessibilityActionsInvoked += 1
        }
    }

    public mutating func recordContextGuard() {
        contextGuardsApplied += 1
        eventsPassedThrough += 1
    }

    public mutating func recordAsyncActionResult(
        kind: AvailableShortcutActionKind,
        succeeded: Bool
    ) {
        switch kind {
        case .menuInvoke:
            if succeeded {
                menuActionsSucceeded += 1
            } else {
                menuActionsFailed += 1
            }
        case .axAction:
            if succeeded {
                accessibilityActionsSucceeded += 1
            } else {
                accessibilityActionsFailed += 1
            }
        case .passthrough, .keyRemap:
            break
        }
    }

    public mutating func merge(_ other: EventTapCounters) {
        keyDownEventsSeen += other.keyDownEventsSeen
        shortcutsMatched += other.shortcutsMatched
        eventsRemapped += other.eventsRemapped
        eventsPassedThrough += other.eventsPassedThrough
        menuActionsInvoked += other.menuActionsInvoked
        menuActionsSucceeded += other.menuActionsSucceeded
        menuActionsFailed += other.menuActionsFailed
        accessibilityActionsInvoked += other.accessibilityActionsInvoked
        accessibilityActionsSucceeded += other.accessibilityActionsSucceeded
        accessibilityActionsFailed += other.accessibilityActionsFailed
        contextGuardsApplied += other.contextGuardsApplied
    }
}

/// Installs a CGEventTap to intercept keyboard events and remap them
/// according to the active adapter for the frontmost application.
///
/// ## How it works
///
/// 1. A Quartz event tap is installed at `kCGSessionEventTap` (between
///    the window server and the frontmost app).
/// 2. On every keyDown / keyUp / flagsChanged event the tap fires a
///    C-function callback.
/// 3. The callback reads the keycode + modifiers, asks the registry to
///    resolve the action, and either:
///    - **remap**: mutates the CGEvent's keycode & flags in-place
///    - **menu/AX**: swallows the event and dispatches the action async
///    - **passthrough**: returns the event unchanged
///
/// The tap must be installed from a thread that has a CFRunLoop. We use
/// a dedicated background thread for this so the main thread stays free
/// for SwiftUI / AppKit.
///
/// ## Why `Unmanaged`?
///
/// CGEventTapCallBack is a C function pointer — it can't capture Swift
/// context. We pass `self` as the `userInfo` void pointer, then recover
/// it inside the callback with `Unmanaged.fromOpaque`.
public final class EventTapManager: ObservableObject {
    public static let enabledDefaultsKey = "Shorty.EventTap.Enabled"
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "app.peyton.shorty",
        category: "EventTap"
    )

    // MARK: - Published state

    /// Whether the event tap is currently active and receiving events.
    @Published public private(set) var isActive: Bool = false

    /// Cumulative event-tap counters useful for diagnostics and support.
    @Published public private(set) var counters = EventTapCounters()

    /// Cumulative count of enabled keyDown events seen by the tap.
    public var eventsIntercepted: Int {
        counters.keyDownEventsSeen
    }

    /// Cumulative count of events that were actually remapped.
    public var eventsRemapped: Int {
        counters.eventsRemapped
    }

    /// Cumulative count of keyDown events that matched a Shorty shortcut.
    public var shortcutsMatched: Int {
        counters.shortcutsMatched
    }

    public func flushPendingDiagnostics() {
        flushDiagnostics()
    }

    /// Last lifecycle note, such as macOS temporarily disabling the tap.
    @Published public private(set) var lifecycleMessage: String?

    /// Last resolved shortcut action, including async menu/AX success when known.
    @Published public private(set) var lastAction: LastShortcutActionDiagnostic?

    /// Whether the tap is enabled (user toggle).
    @Published public var isEnabled: Bool {
        didSet {
            setEnabledSnapshot(isEnabled)
            userDefaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                enableTap()
            } else {
                disableTap()
            }
        }
    }

    /// Optional translation feed for live UI updates and usage tracking.
    public var translationFeed: TranslationFeed?

    // MARK: - Dependencies

    /// Resolves canonical shortcuts → native actions for a given app.
    private let registry: AdapterRegistry

    /// Provides the current frontmost app identifier.
    private let appMonitor: AppMonitor

    private let userDefaults: UserDefaults

    // MARK: - Event tap internals

    /// The Quartz event tap (mach port).
    private var eventTap: CFMachPort?

    /// Run-loop source wrapping the mach port.
    private var runLoopSource: CFRunLoopSource?

    /// The background thread's run loop — needed to remove the source on deinit.
    private var tapRunLoop: CFRunLoop?

    /// Background thread that owns the run loop.
    private var tapThread: Thread?

    private let diagnosticsLock = NSLock()
    private let diagnosticsQueue = DispatchQueue(label: "com.shorty.eventtap.diagnostics")
    private var diagnosticsTimer: DispatchSourceTimer?
    private var pendingCounters = EventTapCounters()
    private let actionQueue = DispatchQueue(label: "com.shorty.eventtap.actions", qos: .userInitiated)
    private let enabledLock = NSLock()
    private var enabledSnapshot = true

    // MARK: - Init / Deinit

    public init(
        registry: AdapterRegistry,
        appMonitor: AppMonitor,
        userDefaults: UserDefaults = .standard
    ) {
        self.registry = registry
        self.appMonitor = appMonitor
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: Self.enabledDefaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = userDefaults.bool(forKey: Self.enabledDefaultsKey)
        }
        setEnabledSnapshot(isEnabled)
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    /// Install and start the event tap. Call once at launch.
    ///
    /// - Returns: `true` if the tap was installed successfully.
    ///   Returns `false` if Accessibility permissions are missing
    ///   (the OS will silently refuse to create the tap).
    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true } // already running
        lifecycleMessage = nil

        // The events we care about: keyDown, keyUp, flagsChanged.
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        // Passing `self` as an opaque pointer for the C callback.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // active — we can modify events
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            // Most likely: user hasn't granted Accessibility permission.
            ShortyLog.eventTap.error("Failed to create CGEvent tap")
            return false
        }

        eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault, tap, 0
        ) else {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
            ShortyLog.eventTap.error("Failed to create event tap run-loop source")
            return false
        }

        runLoopSource = source

        // Spin up a dedicated thread with its own run loop.
        let thread = Thread { [weak self] in
            guard let self = self, let source = self.runLoopSource else { return }
            let runLoop = CFRunLoopGetCurrent()
            self.tapRunLoop = runLoop
            CFRunLoopAddSource(runLoop, source, .commonModes)
            // Run until stopped.
            CFRunLoopRun()
        }
        thread.name = "com.shorty.eventtap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()

        if !currentIsEnabled {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        startDiagnosticsFlush()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isActive = self.currentIsEnabled
        }

        return true
    }

    /// Tear down the event tap and stop the background thread.
    public func stop() {
        stopDiagnosticsFlush()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }

        if let runLoop = tapRunLoop, let source = runLoopSource {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopStop(runLoop)
        }

        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        tapThread = nil

        DispatchQueue.main.async { [weak self] in
            self?.isActive = false
        }
    }

    // MARK: - Tap enable / disable (without tearing down)

    private func enableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        DispatchQueue.main.async { [weak self] in
            self?.isActive = true
        }
    }

    private func disableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        DispatchQueue.main.async { [weak self] in
            self?.isActive = false
        }
    }

    // MARK: - Event handling (called from the C callback)

    /// Process a single keyboard event. Returns the (possibly modified)
    /// event, or `nil` to swallow it.
    fileprivate func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> CGEvent? {

        // If the tap was disabled by the OS (e.g., system went to
        // screensaver and back), re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleTapDisabled(type)
            return event
        }

        // We only remap keyDown events. keyUp and flagsChanged pass through
        // so the OS sees consistent press/release pairs.
        guard type == .keyDown else { return event }

        // Don't intercept if user toggled off.
        guard currentIsEnabled else { return event }

        recordKeyDownEvent()
        let combo = KeyCombo(event: event)
        let appSnapshot = appMonitor.snapshot()

        // Look up the canonical shortcut this combo corresponds to.
        let signpostID = Self.signposter.makeSignpostID()
        let signpost = Self.signposter.beginInterval("ResolveShortcut", id: signpostID)
        defer {
            Self.signposter.endInterval("ResolveShortcut", signpost)
        }
        guard let appID = appSnapshot.effectiveAppID,
              let resolved = registry.resolveShortcut(combo: combo, forApp: appID)
        else {
            // No mapping — pass through unchanged.
            return event
        }

        guard shouldExecute(resolved) else {
            recordContextGuard(resolved, appSnapshot: appSnapshot)
            return event
        }

        switch resolved.action {
        case .remap(let nativeCombo):
            recordResolvedAction(resolved.action)
            recordLastAction(
                resolved,
                appSnapshot: appSnapshot,
                succeeded: true,
                detail: "Remapped to \(nativeCombo.displayString)."
            )
            emitTranslationEvent(
                resolved: resolved,
                appSnapshot: appSnapshot,
                inputKeys: combo,
                actionDescription: "Sends \(nativeCombo.displayString)",
                succeeded: true
            )
            // Mutate the event in place — change keycode and modifier flags.
            event.setIntegerValueField(.keyboardEventKeycode,
                                       value: Int64(nativeCombo.keyCode))
            event.flags = nativeCombo.cgFlags
            return event

        case .invokeMenu(let menuTitle):
            recordResolvedAction(resolved.action)
            recordLastAction(
                resolved,
                appSnapshot: appSnapshot,
                succeeded: nil,
                detail: "Queued menu action \(menuTitle)."
            )
            emitTranslationEvent(
                resolved: resolved,
                appSnapshot: appSnapshot,
                inputKeys: combo,
                actionDescription: "Menu: \(menuTitle)",
                succeeded: nil
            )
            // Swallow the event and trigger the menu item via AX.
            let pid = appSnapshot.currentPID
            let menuPath = resolved.mapping.menuPath
            actionQueue.async { [weak self] in
                let succeeded = MenuIntrospector.invokeMenuItem(
                    pid: pid,
                    title: menuTitle,
                    menuPath: menuPath
                )
                self?.recordAsyncActionResult(
                    resolved,
                    appSnapshot: appSnapshot,
                    succeeded: succeeded,
                    detail: succeeded
                        ? "Invoked menu item \(menuTitle)."
                        : "Could not invoke menu item \(menuTitle)."
                )
                if !succeeded {
                    self?.emitTranslationFailure(
                        resolved: resolved,
                        appSnapshot: appSnapshot,
                        inputKeys: combo,
                        actionDescription: "Could not invoke menu item \(menuTitle)."
                    )
                }
            }
            return nil // swallow

        case .performAXAction(let action):
            recordResolvedAction(resolved.action)
            recordLastAction(
                resolved,
                appSnapshot: appSnapshot,
                succeeded: nil,
                detail: "Queued Accessibility action \(action)."
            )
            emitTranslationEvent(
                resolved: resolved,
                appSnapshot: appSnapshot,
                inputKeys: combo,
                actionDescription: "Action: \(action)",
                succeeded: nil
            )
            // Phase 2+ — placeholder for arbitrary AX actions.
            let pid = appSnapshot.currentPID
            actionQueue.async { [weak self] in
                let succeeded = Self.performAXAction(action, pid: pid)
                self?.recordAsyncActionResult(
                    resolved,
                    appSnapshot: appSnapshot,
                    succeeded: succeeded,
                    detail: succeeded
                        ? "Performed Accessibility action \(action)."
                        : "Could not perform Accessibility action \(action)."
                )
                if !succeeded {
                    self?.emitTranslationFailure(
                        resolved: resolved,
                        appSnapshot: appSnapshot,
                        inputKeys: combo,
                        actionDescription: "Could not perform action \(action)."
                    )
                }
            }
            return nil

        case .passthrough:
            recordResolvedAction(resolved.action)
            recordLastAction(
                resolved,
                appSnapshot: appSnapshot,
                succeeded: true,
                detail: "Allowed the native shortcut through unchanged."
            )
            return event
        }
    }

    private func handleTapDisabled(_ type: CGEventType) {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        let message = type == .tapDisabledByTimeout
            ? "Keyboard tap restarted after macOS paused it."
            : "Keyboard tap restarted after user input disabled it."
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lifecycleMessage = message
            self.isActive = self.currentIsEnabled
        }
        ShortyLog.eventTap.warning("\(message)")
    }

    private var currentIsEnabled: Bool {
        enabledLock.lock()
        defer { enabledLock.unlock() }
        return enabledSnapshot
    }

    private func setEnabledSnapshot(_ isEnabled: Bool) {
        enabledLock.lock()
        enabledSnapshot = isEnabled
        enabledLock.unlock()
    }

    private func shouldExecute(
        _ resolution: AdapterRegistry.ResolvedShortcutAction
    ) -> Bool {
        guard !requiresConservativeContextGuard(resolution) else {
            return resolution.mapping.context != nil
        }
        return true
    }

    private func requiresConservativeContextGuard(
        _ resolution: AdapterRegistry.ResolvedShortcutAction
    ) -> Bool {
        let dangerousIDs: Set<String> = [
            "submit_field",
            "newline_in_field",
            "toggle_play_pause",
            "close_tab",
            "close_window"
        ]
        guard dangerousIDs.contains(resolution.canonicalID) else { return false }
        guard resolution.action != .passthrough else { return false }
        return true
    }

    // MARK: - Diagnostics

    private func recordKeyDownEvent() {
        diagnosticsLock.lock()
        pendingCounters.recordKeyDownEvent()
        diagnosticsLock.unlock()
    }

    private func recordResolvedAction(_ action: AdapterRegistry.ResolvedAction) {
        diagnosticsLock.lock()
        pendingCounters.recordResolvedAction(action)
        diagnosticsLock.unlock()
    }

    private func recordContextGuard(
        _ resolution: AdapterRegistry.ResolvedShortcutAction,
        appSnapshot: AppMonitor.Snapshot
    ) {
        diagnosticsLock.lock()
        pendingCounters.recordContextGuard()
        diagnosticsLock.unlock()
        recordLastAction(
            resolution,
            appSnapshot: appSnapshot,
            succeeded: true,
            detail: "Passed through because this shortcut needs explicit context approval."
        )
    }

    private func recordAsyncActionResult(
        _ resolution: AdapterRegistry.ResolvedShortcutAction,
        appSnapshot: AppMonitor.Snapshot,
        succeeded: Bool,
        detail: String
    ) {
        diagnosticsLock.lock()
        pendingCounters.recordAsyncActionResult(
            kind: actionKind(for: resolution.mapping),
            succeeded: succeeded
        )
        diagnosticsLock.unlock()
        recordLastAction(
            resolution,
            appSnapshot: appSnapshot,
            succeeded: succeeded,
            detail: detail
        )
    }

    private func recordLastAction(
        _ resolution: AdapterRegistry.ResolvedShortcutAction,
        appSnapshot: AppMonitor.Snapshot,
        succeeded: Bool?,
        detail: String
    ) {
        let diagnostic = LastShortcutActionDiagnostic(
            appIdentifier: appSnapshot.effectiveAppID,
            appName: appSnapshot.currentAppName,
            canonicalID: resolution.canonicalID,
            actionKind: actionKind(for: resolution.mapping),
            actionDescription: actionDescription(for: resolution),
            succeeded: succeeded,
            detail: detail
        )
        DispatchQueue.main.async { [weak self] in
            self?.lastAction = diagnostic
        }
    }

    private func actionKind(for mapping: Adapter.Mapping) -> AvailableShortcutActionKind {
        switch mapping.method {
        case .keyRemap:
            return .keyRemap
        case .menuInvoke:
            return .menuInvoke
        case .axAction:
            return .axAction
        case .passthrough:
            return .passthrough
        }
    }

    private func actionDescription(
        for resolution: AdapterRegistry.ResolvedShortcutAction
    ) -> String {
        switch resolution.action {
        case .remap(let combo):
            return "Sends \(combo.displayString)"
        case .invokeMenu(let title):
            if let path = resolution.mapping.menuPath, !path.isEmpty {
                return "Chooses \(path.joined(separator: " > "))"
            }
            return "Chooses \(title)"
        case .performAXAction(let action):
            return "Performs \(action)"
        case .passthrough:
            return "Uses the app's native shortcut"
        }
    }

    private func startDiagnosticsFlush() {
        guard diagnosticsTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: diagnosticsQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.flushDiagnostics()
        }
        diagnosticsTimer = timer
        timer.resume()
    }

    private func stopDiagnosticsFlush() {
        diagnosticsTimer?.cancel()
        diagnosticsTimer = nil
        flushDiagnostics()
    }

    private func flushDiagnostics() {
        diagnosticsLock.lock()
        let pending = pendingCounters
        pendingCounters = EventTapCounters()
        diagnosticsLock.unlock()

        guard !pending.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.counters.merge(pending)
        }
    }

    // MARK: - Translation feed

    private func emitTranslationEvent(
        resolved: AdapterRegistry.ResolvedShortcutAction,
        appSnapshot: AppMonitor.Snapshot,
        inputKeys: KeyCombo,
        actionDescription: String,
        succeeded: Bool?
    ) {
        guard let feed = translationFeed else { return }
        let canonicalName = registry.canonicalShortcuts.first { $0.id == resolved.canonicalID }?.name
            ?? resolved.canonicalID
        let event = TranslationEvent(
            canonicalID: resolved.canonicalID,
            canonicalName: canonicalName,
            inputKeys: inputKeys,
            appName: appSnapshot.currentAppName ?? "Unknown",
            appIdentifier: resolved.appIdentifier,
            actionKind: actionKind(for: resolved.mapping),
            actionDescription: actionDescription,
            succeeded: succeeded
        )
        feed.post(event)
    }

    private func emitTranslationFailure(
        resolved: AdapterRegistry.ResolvedShortcutAction,
        appSnapshot: AppMonitor.Snapshot,
        inputKeys: KeyCombo,
        actionDescription: String
    ) {
        guard let feed = translationFeed else { return }
        let canonicalName = registry.canonicalShortcuts.first { $0.id == resolved.canonicalID }?.name
            ?? resolved.canonicalID
        let event = TranslationEvent(
            canonicalID: resolved.canonicalID,
            canonicalName: canonicalName,
            inputKeys: inputKeys,
            appName: appSnapshot.currentAppName ?? "Unknown",
            appIdentifier: resolved.appIdentifier,
            actionKind: actionKind(for: resolved.mapping),
            actionDescription: actionDescription,
            succeeded: false
        )
        feed.postFailure(event)
    }

    // MARK: - AX helpers (Phase 2 — basic implementations)

    /// Perform a named AX action on the focused element of the target app.
    private static func performAXAction(_ action: String, pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef
        else { return false }
        let focused = unsafeBitCast(focusedRef, to: AXUIElement.self)
        return AXUIElementPerformAction(focused, action as CFString) == .success
    }
}

// MARK: - C callback (free function)

/// The CGEventTapCallBack — a plain C function with no captures.
/// Recovers the EventTapManager from `userInfo` and delegates.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo)
        .takeUnretainedValue()
    if let result = manager.handleEvent(proxy: proxy, type: type, event: event) {
        return Unmanaged.passUnretained(result)
    }
    return nil // swallow
}
