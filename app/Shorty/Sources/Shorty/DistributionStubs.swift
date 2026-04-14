import ShortyCore
import SwiftUI

// MARK: - Sparkle update stub (#40)

/// Placeholder for Sparkle integration. When Sparkle is bundled as a dependency,
/// this view will show real update check results. For now, it directs users to
/// the GitHub releases page.
struct SparkleUpdateBanner: View {
    let updateStatus: UpdateStatus
    let onCheckForUpdates: () -> Void

    var body: some View {
        if updateStatus.state == .updateAvailable {
            ShortyPanel {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(ShortyBrand.teal)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A new version of Shorty is available")
                            .font(.callout.weight(.semibold))
                        Text("Download the latest version for new features and fixes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Update", action: onCheckForUpdates)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Release notes view (#41)

/// Shows release notes after an update. Reads from a bundled changelog
/// or fetches from the release feed when Sparkle is wired.
struct ReleaseNotesView: View {
    let currentVersion: String

    @State private var dismissed = false

    private static let whatsNewDefaultsKey = "Shorty.WhatsNew.LastShownVersion"

    private var shouldShow: Bool {
        !dismissed && !hasShownForThisVersion
    }

    private var hasShownForThisVersion: Bool {
        UserDefaults.standard.string(forKey: Self.whatsNewDefaultsKey) == currentVersion
    }

    var body: some View {
        if shouldShow {
            ShortyPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("What's New in Shorty \(currentVersion)")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Button {
                            dismissed = true
                            UserDefaults.standard.set(currentVersion, forKey: Self.whatsNewDefaultsKey)
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss release notes")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ReleaseNoteBullet("Live translation activity feed in the popover")
                        ReleaseNoteBullet("App coverage scanning for installed apps")
                        ReleaseNoteBullet("Global settings search across all tabs")
                        ReleaseNoteBullet("Menu bar icon variants for engine state")
                        ReleaseNoteBullet("Failure notifications for broken shortcuts")
                        ReleaseNoteBullet("Usage statistics and daily summary")
                    }
                }
            }
        }
    }
}

private struct ReleaseNoteBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundColor(ShortyBrand.teal)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Crash reporting stub (#42)

/// Stub for crash reporting opt-in. When a real reporting service
/// (e.g., Sentry, Crashlytics) is added, this view collects consent.
struct CrashReportingOptIn: View {
    @State private var isEnabled = UserDefaults.standard.bool(forKey: "Shorty.CrashReporting.Enabled")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Help improve Shorty", isOn: $isEnabled)
                .onChange(of: isEnabled) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "Shorty.CrashReporting.Enabled")
                }
            Text("Send anonymous crash reports when something goes wrong. No personal data is collected.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Adapter-only update stub (#43)

/// Stub for adapter-only updates. When implemented, this will allow
/// downloading new adapter catalogs separately from app updates.
struct AdapterCatalogUpdateView: View {
    let adapterCount: Int
    let builtInCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Adapter Catalog")
                    .font(.callout.weight(.medium))
                Spacer()
                Text("\(adapterCount) adapters loaded")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("Adapter catalog updates will be available in a future release, allowing new app support without a full app update.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Community adapter stub (#29, #31)

/// Stub for the community adapter repository and request system.
struct CommunityAdapterSection: View {
    var body: some View {
        ShortyPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Community")
                        .font(.headline)
                    Text("Coming Soon")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ShortyBrand.teal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ShortyBrand.teal.opacity(0.12), in: Capsule())
                }
                Text("Browse and download community-contributed adapters, or request support for apps you use.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
