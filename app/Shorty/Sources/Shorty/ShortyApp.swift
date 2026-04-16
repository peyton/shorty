import AppKit
import Combine
import ShortyCore
import SwiftUI
import UserNotifications

final class ShortyAppDelegate: NSObject, NSApplicationDelegate {
    let engine = ShortcutEngine(configuration: ShortyAppDelegate.appConfiguration)
    private var didOpenFirstRunSettings = false
    private lazy var settingsWindowPresenter = SettingsWindowPresenter(engine: engine)

    private static var appConfiguration: EngineConfiguration {
#if SHORTY_APP_STORE
        return .appStoreCandidate
#else
        return .releaseDefault
#endif
    }

    let toastManager = ToastManager()
    private var feedCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        engine.start()
        openFirstRunSettingsIfNeeded()
        startTranslationToastObserver()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        engine.refreshDailyStatuses()
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        showSettingsWindow()
    }

    func showSettingsWindow() {
        settingsWindowPresenter.show()
    }

    private func openFirstRunSettingsIfNeeded() {
        guard !didOpenFirstRunSettings, !engine.isFirstRunComplete else { return }
        didOpenFirstRunSettings = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.showSettingsWindow()
        }
    }

    private func startTranslationToastObserver() {
        feedCancellable = engine.translationFeed.$recentEvents
            .dropFirst()
            .compactMap(\.last)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                let settings = self.engine.persistedSettings
                let isFailure = event.succeeded == false

                if isFailure {
                    // Always show failure notifications (#21)
                    self.showFailureNotification(event)
                    self.toastManager.enqueue(event)
                } else if settings.shouldShowToasts {
                    // Show success toasts during learning phase (#1)
                    self.toastManager.enqueue(event)
                    self.engine.updatePersistedSettings { $0.recordToastShown() }
                }
            }
    }

    private func showFailureNotification(_ event: TranslationEvent) {
        let content = UNMutableNotificationContent()
        content.title = "Shortcut failed"
        content.body = "Shorty couldn't execute \(event.canonicalName) in \(event.appName). The shortcut was passed through."
        let request = UNNotificationRequest(
            identifier: "shorty-failure-\(event.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

@main
struct ShortyApp: App {
    @NSApplicationDelegateAdaptor(ShortyAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusBarView(
                engine: appDelegate.engine,
                openSettingsWindow: { appDelegate.showSettingsWindow() }
            )
                .tint(ShortyBrand.teal)
        } label: {
            StatusIconView(engine: appDelegate.engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: appDelegate.engine)
                .tint(ShortyBrand.teal)
        }
    }
}

private struct StatusIconView: View {
    @ObservedObject var engine: ShortcutEngine

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(renderingMode)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 18, height: 18)
            .accessibilityLabel(engine.status.title)
            .help(engine.status.title)
    }

    /// Menu bar icon variants (#23): distinct treatments for each engine state.
    private var iconName: String {
        switch engine.status {
        case .running:
            if engine.eventTap.isEnabled {
                return "keyboard.fill"
            }
            return "keyboard"
        case .disabled:
            return "keyboard.badge.ellipsis"
        case .permissionRequired:
            return "keyboard.badge.eye"
        case .failed:
            return "exclamationmark.triangle"
        case .starting:
            return "keyboard"
        case .stopped:
            return "keyboard"
        }
    }

    private var renderingMode: SymbolRenderingMode {
        switch engine.status {
        case .running where engine.eventTap.isEnabled:
            return .monochrome
        case .permissionRequired, .failed:
            return .multicolor
        default:
            return .monochrome
        }
    }
}
