import AppKit
import ShortyCore
import SwiftUI

try renderScreenshots()

private func renderScreenshots() throws {
    NSApplication.shared.setActivationPolicy(.prohibited)

    let outputDirectory = outputDirectoryURL()
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )

    let fixtures = ScreenshotFixtures()
    let renderer = ScreenshotRenderer(outputDirectory: outputDirectory)
    try renderer.renderAll(fixtures: fixtures)
    print("Wrote Shorty marketing screenshots to \(outputDirectory.path)")
}

private func outputDirectoryURL() -> URL {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("web/assets/screenshots", isDirectory: true)
}

private struct ScreenshotRenderer {
    let outputDirectory: URL

    func renderAll(fixtures: ScreenshotFixtures) throws {
        try render(
            NativeSettingsWindow(
                title: "Shortcuts",
                snapshot: fixtures.settings,
                initialTab: .shortcuts
            ),
            name: "native-settings-shortcuts.png",
            size: CGSize(width: 840, height: 660),
            scale: 2
        )

        try render(
            NativeSettingsWindow(
                title: "Apps",
                snapshot: fixtures.settings,
                initialTab: .adapters
            ),
            name: "native-settings-apps.png",
            size: CGSize(width: 840, height: 660),
            scale: 2
        )

        try render(
            NativeStatusPopover(snapshot: fixtures.activeStatus),
            name: "native-status-popover.png",
            size: CGSize(width: 500, height: 640),
            scale: 2
        )

        try render(
            NativeStatusPopover(snapshot: fixtures.permissionStatus),
            name: "native-status-permission.png",
            size: CGSize(width: 500, height: 640),
            scale: 2
        )

        try render(
            NativeStatusPopover(snapshot: fixtures.pausedStatus),
            name: "native-status-paused.png",
            size: CGSize(width: 500, height: 640),
            scale: 2
        )

        try render(
            NativeStatusPopover(snapshot: fixtures.noAdapterStatus),
            name: "native-status-no-adapter.png",
            size: CGSize(width: 500, height: 640),
            scale: 2
        )

        try renderStoreShot(
            name: "app-store-shortcuts.png",
            title: "One shortcut set across your Mac.",
            subtitle: "Press the shortcut you already know. Shorty translates it for the app in front.",
            accent: "Consistent shortcuts",
            visual: ShortcutsMarketingVisual(fixtures: fixtures)
        )

        try renderStoreShot(
            name: "app-store-apps.png",
            title: "Native apps and supported web apps.",
            subtitle: "Built-in adapters cover common Mac apps. The browser bridge is explicit and optional.",
            accent: "Local adapters",
            visual: AppsMarketingVisual(fixtures: fixtures)
        )

        try renderStoreShot(
            name: "app-store-setup.png",
            title: "Local-first from the first launch.",
            subtitle: "Shorty asks for the macOS permission it needs, keeps setup visible, and ships with checksums.",
            accent: "Private by default",
            visual: SetupMarketingVisual(fixtures: fixtures)
        )

        try renderWebShot(
            name: "web-hero.png",
            title: "One shortcut set across your Mac.",
            subtitle: "Shorty runs in the menu bar and translates shortcuts locally for supported apps.",
            accent: "macOS menu bar shortcuts",
            visual: ShortcutsMarketingVisual(fixtures: fixtures)
        )

        try renderWebShot(
            name: "web-apps.png",
            title: "Native apps and supported web apps.",
            subtitle: "Adapters stay reviewable, local, and limited to the apps you choose.",
            accent: "adapter coverage",
            visual: AppsMarketingVisual(fixtures: fixtures)
        )

        try renderWebShot(
            name: "web-setup.png",
            title: "Download, verify, allow.",
            subtitle: "A direct download, a visible checksum, and clear Accessibility setup.",
            accent: "release trust",
            visual: SetupMarketingVisual(fixtures: fixtures)
        )
    }

    private func renderStoreShot<Visual: View>(
        name: String,
        title: String,
        subtitle: String,
        accent: String,
        visual: Visual
    ) throws {
        try render(
            MarketingCanvas(
                title: title,
                subtitle: subtitle,
                accent: accent,
                visual: visual
            ),
            name: name,
            size: CGSize(width: 2880, height: 1800),
            scale: 1
        )
    }

    private func renderWebShot<Visual: View>(
        name: String,
        title: String,
        subtitle: String,
        accent: String,
        visual: Visual
    ) throws {
        try render(
            MarketingCanvas(
                title: title,
                subtitle: subtitle,
                accent: accent,
                visual: visual
            ),
            name: name,
            size: CGSize(width: 1600, height: 1000),
            scale: 1
        )
    }

    private func render<Content: View>(
        _ content: Content,
        name: String,
        size: CGSize,
        scale: CGFloat
    ) throws {
        let url = outputDirectory.appendingPathComponent(name)
        let view = NSHostingView(
            rootView: content
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .light)
        )
        view.frame = CGRect(origin: .zero, size: size)
        view.wantsLayer = true
        view.appearance = NSAppearance(named: .aqua)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let rep else {
            throw ScreenshotError.couldNotCreateBitmap(name)
        }

        rep.size = size
        view.cacheDisplay(in: view.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.couldNotEncodePNG(name)
        }

        try data.write(to: url, options: .atomic)
    }
}

private enum ScreenshotError: Error, CustomStringConvertible {
    case couldNotCreateBitmap(String)
    case couldNotEncodePNG(String)

    var description: String {
        switch self {
        case .couldNotCreateBitmap(let name):
            return "Could not create bitmap for \(name)."
        case .couldNotEncodePNG(let name):
            return "Could not encode PNG for \(name)."
        }
    }
}

private struct ScreenshotFixtures {
    let settings: SettingsSnapshot
    let activeStatus: StatusBarSnapshot
    let permissionStatus: StatusBarSnapshot
    let pausedStatus: StatusBarSnapshot
    let noAdapterStatus: StatusBarSnapshot

    init() {
        let activeAvailability = Self.availability(
            for: "com.linear",
            displayName: "Linear"
        )
        let safariAvailability = Self.availability(
            for: "com.apple.Safari",
            displayName: "Safari"
        )
        let noAdapterAvailability = ShortcutAvailability(
            state: .noAdapter,
            appIdentifier: "com.example.notes",
            appDisplayName: "Acme Notes"
        )

        settings = SettingsSnapshot(
            shortcuts: CanonicalShortcut.defaults,
            shortcutProfile: .releaseDefault,
            shortcutConflicts: UserShortcutProfile.releaseDefault.conflicts(),
            adapters: Self.adapters,
            validationMessages: [],
            adapterGenerationMessage: "Generated 6 mappings for Things. Review before saving.",
            generatedAdapterPreview: nil,
            generatedAdapterReview: nil,
            adapterRevisions: [],
            versionBuild: "1.0.0 (1)",
            engineStatus: "Shorty is active",
            accessibilityStatus: "Granted",
            browserBridgeStatus: "Browser bridge ready",
            bridgeInstallStatuses: [],
            safariExtensionStatus: SafariExtensionStatus(
                state: .bundled,
                detail: "The Safari extension is included with this build. Enable it in Safari Settings before using web-app adapters in Safari."
            ),
            launchAtLoginStatus: LaunchAtLoginStatus(
                state: .enabled,
                detail: "Shorty will open automatically when you sign in."
            ),
            updateStatus: UpdateStatus(
                state: .idle,
                currentVersion: "1.0.0",
                automaticChecksEnabled: true,
                detail: "Updates are ready for signed direct-download builds."
            ),
            firstRunComplete: true,
            globalPauseUntil: nil,
            feedbackMessage: nil,
            diagnostics: RuntimeDiagnosticSnapshot(
                engineStatus: "Shorty is active",
                permissionState: .granted,
                currentAppName: "Linear",
                currentBundleID: "com.linear",
                effectiveAppID: "com.linear",
                browserContextSource: .none,
                webDomain: nil,
                bridgeStatus: "Browser bridge ready",
                safariExtensionStatus: SafariExtensionStatus(
                    state: .bundled,
                    detail: "The Safari extension is included with this build."
                ),
                eventsIntercepted: 184,
                eventsMatched: 82,
                eventsRemapped: 57,
                eventsPassedThrough: 21,
                menuActionsInvoked: 4,
                accessibilityActionsInvoked: 0,
                contextGuardsApplied: 0,
                adapterValidationMessages: []
            ),
            displayStatus: EngineDisplayStatus.make(
                status: .running,
                permissionState: .granted,
                eventTapEnabled: true,
                isWaitingForPermission: false
            ),
            activeAppName: "Linear",
            activeAvailability: activeAvailability,
            isWaitingForAccessibilityPermission: false
        )

        activeStatus = StatusBarSnapshot(
            status: EngineDisplayStatus.make(
                status: .running,
                permissionState: .granted,
                eventTapEnabled: true,
                isWaitingForPermission: false
            ),
            currentAppName: "Linear",
            activeContextTitle: "Linear",
            availability: activeAvailability,
            lifecycleMessage: nil,
            effectiveID: "com.linear",
            adapterSource: "Built-in",
            mappingCount: "\(activeAvailability.shortcuts.count)",
            webDomain: "None",
            browserContextSource: "No browser context",
            bridgeStatus: "Browser bridge ready",
            safariExtensionStatus: "Safari extension bundled",
            shortcutReviewCount: UserShortcutProfile.releaseDefault.conflicts().count,
            eventsIntercepted: 184,
            eventsMatched: 82,
            eventsRemapped: 57,
            eventsPassedThrough: 21,
            menuActionsInvoked: 4,
            accessibilityActionsInvoked: 0,
            contextGuardsApplied: 0,
            validationMessages: [],
            adapterGenerationMessage: nil,
            hasGeneratedAdapterPreview: false
        )

        permissionStatus = StatusBarSnapshot(
            status: EngineDisplayStatus.make(
                status: .permissionRequired,
                permissionState: .notGranted,
                eventTapEnabled: true,
                isWaitingForPermission: true
            ),
            currentAppName: "Safari",
            activeContextTitle: "Safari",
            availability: safariAvailability,
            lifecycleMessage: nil,
            effectiveID: "com.apple.Safari",
            adapterSource: "Built-in",
            mappingCount: "\(safariAvailability.shortcuts.count)",
            webDomain: "None",
            browserContextSource: "No browser context",
            bridgeStatus: "Browser bridge stopped",
            safariExtensionStatus: "Safari extension disabled",
            shortcutReviewCount: UserShortcutProfile.releaseDefault.conflicts().count,
            eventsIntercepted: 0,
            eventsMatched: 0,
            eventsRemapped: 0,
            eventsPassedThrough: 0,
            menuActionsInvoked: 0,
            accessibilityActionsInvoked: 0,
            contextGuardsApplied: 0,
            validationMessages: [],
            adapterGenerationMessage: nil,
            hasGeneratedAdapterPreview: false
        )

        pausedStatus = StatusBarSnapshot(
            status: EngineDisplayStatus.make(
                status: .disabled,
                permissionState: .granted,
                eventTapEnabled: false,
                isWaitingForPermission: false
            ),
            currentAppName: "Linear",
            activeContextTitle: "Linear",
            availability: activeAvailability,
            lifecycleMessage: nil,
            effectiveID: "com.linear",
            adapterSource: "Built-in",
            mappingCount: "\(activeAvailability.shortcuts.count)",
            webDomain: "None",
            browserContextSource: "No browser context",
            bridgeStatus: "Browser bridge ready",
            safariExtensionStatus: "Safari extension bundled",
            shortcutReviewCount: UserShortcutProfile.releaseDefault.conflicts().count,
            eventsIntercepted: 184,
            eventsMatched: 82,
            eventsRemapped: 57,
            eventsPassedThrough: 21,
            menuActionsInvoked: 4,
            accessibilityActionsInvoked: 0,
            contextGuardsApplied: 0,
            validationMessages: [],
            adapterGenerationMessage: nil,
            hasGeneratedAdapterPreview: false
        )

        noAdapterStatus = StatusBarSnapshot(
            status: EngineDisplayStatus.make(
                status: .running,
                permissionState: .granted,
                eventTapEnabled: true,
                isWaitingForPermission: false
            ),
            currentAppName: "Acme Notes",
            activeContextTitle: "Acme Notes",
            availability: noAdapterAvailability,
            lifecycleMessage: nil,
            effectiveID: "com.example.notes",
            adapterSource: "none",
            mappingCount: "0",
            webDomain: "None",
            browserContextSource: "No browser context",
            bridgeStatus: "Browser bridge ready",
            safariExtensionStatus: "Safari extension bundled",
            shortcutReviewCount: UserShortcutProfile.releaseDefault.conflicts().count,
            eventsIntercepted: 184,
            eventsMatched: 82,
            eventsRemapped: 57,
            eventsPassedThrough: 21,
            menuActionsInvoked: 4,
            accessibilityActionsInvoked: 0,
            contextGuardsApplied: 0,
            validationMessages: [],
            adapterGenerationMessage: "No matching shortcuts were found in Acme Notes.",
            hasGeneratedAdapterPreview: false
        )
    }

    private static func availability(
        for appID: String,
        displayName: String
    ) -> ShortcutAvailability {
        AdapterRegistry(appSupportDirectory: temporaryAppSupportDirectory())
            .availability(for: appID, displayName: displayName)
    }

    private static func temporaryAppSupportDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortyScreenshots", isDirectory: true)
    }

    private static var adapters: [Adapter] {
        [
            Adapter(
                appIdentifier: "com.google.Chrome",
                appName: "Google Chrome",
                mappings: [
                    .init(canonicalID: "focus_url_bar", method: .passthrough),
                    .init(canonicalID: "find_in_page", method: .passthrough),
                    .init(canonicalID: "new_tab", method: .passthrough),
                    .init(canonicalID: "close_tab", method: .passthrough),
                    .init(canonicalID: "reopen_tab", method: .passthrough)
                ]
            ),
            Adapter(
                appIdentifier: "com.apple.finder",
                appName: "Finder",
                mappings: [
                    .init(
                        canonicalID: "focus_url_bar",
                        method: .keyRemap,
                        nativeKeys: KeyCombo(keyCode: 0x25, modifiers: [.command, .shift])
                    ),
                    .init(canonicalID: "find_in_page", method: .passthrough),
                    .init(canonicalID: "new_tab", method: .passthrough)
                ]
            ),
            Adapter(
                appIdentifier: "com.linear",
                appName: "Linear",
                mappings: [
                    .init(
                        canonicalID: "command_palette",
                        method: .keyRemap,
                        nativeKeys: KeyCombo(keyCode: 0x28, modifiers: .command)
                    ),
                    .init(canonicalID: "find_in_page", method: .passthrough)
                ]
            ),
            Adapter(
                appIdentifier: "web:mail.google.com",
                appName: "Gmail Web",
                mappings: [
                    .init(canonicalID: "focus_url_bar", method: .passthrough),
                    .init(canonicalID: "find_in_page", method: .passthrough),
                    .init(
                        canonicalID: "submit_field",
                        method: .keyRemap,
                        nativeKeys: KeyCombo(keyCode: 0x24, modifiers: .command)
                    ),
                    .init(canonicalID: "newline_in_field", method: .passthrough)
                ]
            ),
            Adapter(
                appIdentifier: "web:figma.com",
                appName: "Figma Web",
                mappings: [
                    .init(canonicalID: "focus_url_bar", method: .passthrough),
                    .init(canonicalID: "find_in_page", method: .passthrough),
                    .init(
                        canonicalID: "command_palette",
                        method: .keyRemap,
                        nativeKeys: KeyCombo(keyCode: 0x2C, modifiers: .command)
                    )
                ]
            ),
            Adapter(
                appIdentifier: "com.culturedcode.ThingsMac",
                appName: "Things",
                source: .menuIntrospection,
                mappings: [
                    .init(
                        canonicalID: "command_palette",
                        method: .menuInvoke,
                        menuTitle: "Quick Find"
                    ),
                    .init(
                        canonicalID: "new_window",
                        method: .menuInvoke,
                        menuTitle: "New Window"
                    )
                ]
            )
        ]
    }
}

private struct NativeSettingsWindow: View {
    let title: String
    let snapshot: SettingsSnapshot
    let initialTab: SettingsTab

    var body: some View {
        MacWindowFrame(title: title) {
            SettingsContentView(
                snapshot: snapshot,
                initialTab: initialTab
            )
            .frame(width: 780, height: 560)
        }
        .padding(20)
        .background(ScreenshotPalette.backdrop)
    }
}

private struct NativeStatusPopover: View {
    let snapshot: StatusBarSnapshot

    var body: some View {
        PopoverFrame {
            StatusBarContentView(
                snapshot: snapshot,
                eventTapEnabled: .constant(
                    !snapshot.requiresPermission && snapshot.status.title != "Paused"
                ),
                showsDetails: snapshot.status.title == "Paused"
            )
        }
        .padding(24)
        .background(ScreenshotPalette.backdrop)
    }
}

private struct MarketingCanvas<Visual: View>: View {
    let title: String
    let subtitle: String
    let accent: String
    let visual: Visual

    var body: some View {
        GeometryReader { proxy in
            canvas(size: proxy.size)
        }
    }

    private func canvas(size: CGSize) -> some View {
        let unit = min(size.width / 2880, size.height / 1800)

        return ZStack(alignment: .bottomLeading) {
            ScreenshotPalette.canvasBackground
                .ignoresSafeArea()

            HStack(alignment: .center, spacing: 90 * unit) {
                VStack(alignment: .leading, spacing: 36 * unit) {
                    BrandLockup(unit: unit)

                    Text(accent.uppercased())
                        .font(.system(size: 30 * unit, weight: .bold))
                        .tracking(0)
                        .foregroundStyle(ScreenshotPalette.green)

                    Text(title)
                        .font(.system(size: 112 * unit, weight: .black, design: .rounded))
                        .foregroundStyle(ScreenshotPalette.ink)
                        .lineSpacing(-6 * unit)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.system(size: 42 * unit, weight: .medium))
                        .foregroundStyle(ScreenshotPalette.muted)
                        .lineSpacing(10 * unit)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 840 * unit, alignment: .leading)

                visual
                    .scaleEffect(unit, anchor: .center)
                    .frame(width: 1460 * unit, height: 1040 * unit)
            }
            .padding(.horizontal, 190 * unit)
            .frame(width: size.width, height: size.height)

            Text("Shorty for macOS")
                .font(.system(size: 30 * unit, weight: .semibold))
                .foregroundStyle(ScreenshotPalette.subtle)
                .padding(.leading, 190 * unit)
                .padding(.bottom, 104 * unit)
        }
    }
}

private struct ShortcutsMarketingVisual: View {
    let fixtures: ScreenshotFixtures

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MacWindowFrame(title: "Shortcuts") {
                SettingsContentView(
                    snapshot: fixtures.settings,
                    initialTab: .shortcuts
                )
                .frame(width: 780, height: 560)
            }
            .scaleEffect(1.18)
            .offset(x: -116, y: -74)

            PopoverFrame {
                StatusBarContentView(
                    snapshot: fixtures.activeStatus,
                    eventTapEnabled: .constant(true),
                    showsDetails: true
                )
            }
            .frame(width: 430)
            .offset(x: 28, y: 58)
        }
        .frame(width: 1460, height: 1040)
    }
}

private struct AppsMarketingVisual: View {
    let fixtures: ScreenshotFixtures

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MacWindowFrame(title: "Apps") {
                SettingsContentView(
                    snapshot: fixtures.settings,
                    initialTab: .adapters
                )
                .frame(width: 780, height: 560)
            }
            .scaleEffect(1.24)
            .offset(x: -88, y: 22)

            AdapterBadge(title: "Browser Bridge", value: "optional")
                .offset(x: 20, y: -52)
        }
        .frame(width: 1460, height: 1040)
    }
}

private struct SetupMarketingVisual: View {
    let fixtures: ScreenshotFixtures

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TrustPanel()
                .offset(x: 570, y: -90)

            PopoverFrame {
                StatusBarContentView(
                    snapshot: fixtures.permissionStatus,
                    eventTapEnabled: .constant(false)
                )
            }
            .frame(width: 540)
            .offset(x: 110, y: 30)

            ChecksumPanel()
                .offset(x: 620, y: 500)
        }
        .frame(width: 1460, height: 1040)
    }
}

private struct MacWindowFrame<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle().fill(Color(red: 1, green: 0.36, blue: 0.31))
                Circle().fill(Color(red: 1, green: 0.78, blue: 0.25))
                Circle().fill(Color(red: 0.24, green: 0.82, blue: 0.39))
                Spacer()
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 62)
            }
            .frame(height: 52)
            .padding(.horizontal, 20)
            .background(Color(nsColor: .windowBackgroundColor))

            content
                .environment(\.colorScheme, .dark)
                .background(ScreenshotPalette.panelDark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 40, x: 0, y: 24)
    }
}

private struct PopoverFrame<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.colorScheme, .dark)
            .background(ScreenshotPalette.panelDark)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 34, x: 0, y: 20)
    }
}

private struct BrandLockup: View {
    let unit: CGFloat

    var body: some View {
        HStack(spacing: 20 * unit) {
            BrandMark(unit: unit)
            Text("Shorty")
                .font(.system(size: 48 * unit, weight: .black, design: .rounded))
                .foregroundStyle(ScreenshotPalette.ink)
        }
    }
}

private struct BrandMark: View {
    let unit: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12 * unit, style: .continuous)
            .fill(ScreenshotPalette.ink)
            .frame(width: 68 * unit, height: 68 * unit)
            .overlay {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 36 * unit, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(ScreenshotPalette.green)
                    .frame(width: 36 * unit, height: 7 * unit)
                    .offset(y: -10 * unit)
            }
    }
}

private struct AdapterBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
            Text(value.uppercased())
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(ScreenshotPalette.green)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .background(.white)
        .foregroundStyle(ScreenshotPalette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 24, x: 0, y: 16)
    }
}

private struct TrustPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            TrustRow(icon: "lock.shield.fill", title: "No account", value: "Local shortcut matching")
            TrustRow(icon: "wifi.slash", title: "No cloud service", value: "Native shortcuts stay on device")
            TrustRow(icon: "checkmark.seal.fill", title: "Reviewed adapters", value: "Generated adapters wait for approval")
        }
        .padding(42)
        .frame(width: 620, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 32, x: 0, y: 20)
    }
}

private struct TrustRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(ScreenshotPalette.green)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(ScreenshotPalette.ink)
                Text(value)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(ScreenshotPalette.muted)
            }
        }
    }
}

private struct ChecksumPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Checksum command")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(ScreenshotPalette.muted)
            Text("shasum -a 256 shorty-1.0.0-macos.zip")
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(ScreenshotPalette.ink)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .background(ScreenshotPalette.lightGreen)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(ScreenshotPalette.green.opacity(0.18), lineWidth: 1)
        )
    }
}

private enum ScreenshotPalette {
    static let ink = Color(red: 0.06, green: 0.09, blue: 0.08)
    static let muted = Color(red: 0.29, green: 0.35, blue: 0.33)
    static let subtle = Color(red: 0.42, green: 0.49, blue: 0.46)
    static let green = Color(red: 0.05, green: 0.54, blue: 0.38)
    static let lightGreen = Color(red: 0.89, green: 0.96, blue: 0.92)
    static let backdrop = Color(red: 0.92, green: 0.96, blue: 0.94)
    static let panelDark = Color(red: 0.11, green: 0.12, blue: 0.12)

    static var canvasBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.99, blue: 0.98),
                Color(red: 0.90, green: 0.96, blue: 0.93)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
