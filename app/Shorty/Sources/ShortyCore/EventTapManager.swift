import AppKit
import Combine
import CoreGraphics

public struct EventTapCounters: Codable, Equatable {
    public private(set) var keyDownEventsSeen: Int
    public private(set) var shortcutsMatched: Int
    public private(set) var eventsRemapped: Int
    public private(set) var eventsPassedThrough: Int
    public private(set) var menuActionsInvoked: Int
    public private(set) var accessibilityActionsInvoked: Int

    public init(
        keyDownEventsSeen: Int = 0,
        shortcutsMatched: Int = 0,
        eventsRemapped: Int = 0,
        eventsPassedThrough: Int = 0,
        menuActionsInvoked: Int = 0,
        accessibilityActionsInvoked: Int = 0
    ) {
        self.keyDownEventsSeen = keyDownEventsSeen
        self.shortcutsMatched = shortcutsMatched
        self.eventsRemapped = eventsRemapped
        self.eventsPassedThrough = eventsPassedThrough
        self.menuActionsInvoked = menuActionsInvoked
        self.accessibilityActionsInvoked = accessibilityActionsInvoked
    }

    public var isEmpty: Bool {
        keyDownEventsSeen == 0
            && shortcutsMatched == 0
            && eventsRemapped == 0
            && eventsPassedThrough == 0
            && menuActionsInvoked == 0
            && accessibilityActionsInvoked == 0
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

    public mutating func merge(_ other: EventTapCounters) {
        keyDownEventsSeen += other.keyDownEventsSeen
        shortcutsMatched += other.shortcutsMatched
        eventsRemapped += other.eventsRemapped
        eventsPassedThrough += other.eventsPassedThrough
        menuActionsInvoked += other.menuActionsInvoked
        accessibilityActionsInvoked += other.accessibilityActionsInvoked
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

    /// Last lifecycle note, such as macOS temporarily disabling the tap.
    @Published public private(set) var lifecycleMessage: String?

    /// Whether the tap is enabled (user toggle).
    @Published public var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
            if isEnabled {
                enableTap()
            } else {
                disableTap()
            }
        }
    }

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

        if !isEnabled {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        startDiagnosticsFlush()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isActive = self.isEnabled
        }

        return true
    }

    /// Tear down the event tap and stop the background thread.
    public func stop() {
        stopDiagnosticsFlush()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
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
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            let message = type == .tapDisabledByTimeout
                ? "Keyboard tap restarted after macOS paused it."
                : "Keyboard tap restarted after user input disabled it."
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lifecycleMessage = message
                self.isActive = self.isEnabled
            }
            ShortyLog.eventTap.warning("\(message)")
            return event
        }

        // We only remap keyDown events. keyUp and flagsChanged pass through
        // so the OS sees consistent press/release pairs.
        guard type == .keyDown else { return event }

        // Don't intercept if user toggled off.
        guard isEnabled else { return event }

        recordKeyDownEvent()
        let combo = KeyCombo(event: event)

        // Look up the canonical shortcut this combo corresponds to.
        guard let appID = appMonitor.effectiveAppID,
              let resolved = registry.resolve(combo: combo, forApp: appID)
        else {
            // No mapping — pass through unchanged.
            return event
        }

        switch resolved {
        case .remap(let nativeCombo):
            recordResolvedAction(resolved)
            // Mutate the event in place — change keycode and modifier flags.
            event.setIntegerValueField(.keyboardEventKeycode,
                                       value: Int64(nativeCombo.keyCode))
            event.flags = nativeCombo.cgFlags
            return event

        case .invokeMenu(let menuTitle):
            recordResolvedAction(resolved)
            // Swallow the event and trigger the menu item via AX.
            let pid = appMonitor.currentPID
            actionQueue.async {
                Self.invokeMenuItem(title: menuTitle, pid: pid)
            }
            return nil // swallow

        case .performAXAction(let action):
            recordResolvedAction(resolved)
            // Phase 2+ — placeholder for arbitrary AX actions.
            let pid = appMonitor.currentPID
            actionQueue.async {
                Self.performAXAction(action, pid: pid)
            }
            return nil

        case .passthrough:
            recordResolvedAction(resolved)
            return event
        }
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

    // MARK: - AX helpers (Phase 2 — basic implementations)

    /// Walk the app's menu bar to find and press a menu item by title.
    private static func invokeMenuItem(title: String, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarRef
        else { return }
        let menuBar = unsafeBitCast(menuBarRef, to: AXUIElement.self)

        // Walk top-level menus → items
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar,
                                            kAXChildrenAttribute as CFString,
                                            &childrenRef) == .success,
              let menus = childrenRef as? [AXUIElement]
        else { return }

        for menu in menus {
            if let item = findMenuItem(in: menu, title: title) {
                AXUIElementPerformAction(item, kAXPressAction as CFString)
                return
            }
        }
    }

    /// Recursively search for a menu item matching the given title.
    private static func findMenuItem(in element: AXUIElement, title: String) -> AXUIElement? {
        // Check this element's title
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let elementTitle = titleRef as? String, elementTitle == title {
            return element
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return nil }

        for child in children {
            if let found = findMenuItem(in: child, title: title) {
                return found
            }
        }
        return nil
    }

    /// Perform a named AX action on the focused element of the target app.
    private static func performAXAction(_ action: String, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef
        else { return }
        let focused = unsafeBitCast(focusedRef, to: AXUIElement.self)
        AXUIElementPerformAction(focused, action as CFString)
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
