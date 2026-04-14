import AppKit
import ShortyCore
import SwiftUI

// MARK: - VoiceOver helpers (#36)

/// Accessibility helpers for consistent VoiceOver behavior across the app.
extension View {
    /// Adds a descriptive accessibility label and removes children from VoiceOver traversal.
    func accessibleCombined(label: String) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
    }

    /// Applies reduce-motion preference to animations (#38).
    func reduceMotionSafe<V: Equatable>(
        _ animation: Animation,
        value: V
    ) -> some View {
        self.animation(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation,
            value: value
        )
    }
}

// MARK: - Dynamic Type scaling helpers (#39)

/// Scaled font that respects Dynamic Type preferences.
struct ScaledFont: ViewModifier {
    let style: Font.TextStyle
    let design: Font.Design

    func body(content: Content) -> some View {
        content
            .font(.system(style, design: design))
    }
}

extension View {
    func scaledFont(_ style: Font.TextStyle, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(style: style, design: design))
    }
}

// MARK: - Keyboard navigation helpers (#37)

/// Focus-ring styling for keyboard navigation in Settings.
struct FocusRingModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(ShortyBrand.teal.opacity(0.5), lineWidth: 2)
                }
            }
    }
}

extension View {
    func focusRing(_ isFocused: Bool) -> some View {
        modifier(FocusRingModifier(isFocused: isFocused))
    }
}

// MARK: - Accessibility identifiers catalog (#36)

/// Central catalog of accessibility identifiers for UI testing and VoiceOver.
enum AccessibilityID {
    static let statusPopover = "status-popover"
    static let statusHeader = "status-header"
    static let translationToggle = "translation-toggle"
    static let liveFeedTab = "live-feed-tab"
    static let availableTab = "available-tab"
    static let popoverSearch = "popover-search"
    static let bridgeIndicator = "bridge-indicator"
    static let usageSummary = "usage-summary"

    static let settingsSearch = "settings-search"
    static let settingsUndo = "settings-undo"
    static let setupTab = "setup-tab"
    static let shortcutsTab = "shortcuts-tab"
    static let appsTab = "apps-tab"
    static let advancedTab = "advanced-tab"
    static let appScanButton = "app-scan-button"
    static let coverageSummary = "coverage-summary"

    static let preferencesToasts = "prefs-toasts"
    static let preferencesCompact = "prefs-compact"
    static let preferencesSound = "prefs-sound"
    static let preferencesDigest = "prefs-digest"
}
