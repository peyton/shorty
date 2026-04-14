import XCTest
@testable import ShortyCore

final class AppMonitorIntegrationTests: XCTestCase {

    func testIgnoredApplicationActivationKeepsPreviousAppContext() {
        let monitor = AppMonitor(ignoredBundleIdentifiers: ["app.peyton.shorty"])

        XCTAssertTrue(monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 101
        ))
        XCTAssertFalse(monitor.updateActiveApplication(
            bundleIdentifier: "app.peyton.shorty",
            localizedName: "Shorty",
            processIdentifier: 102
        ))

        XCTAssertEqual(monitor.currentBundleID, "com.apple.Safari")
        XCTAssertEqual(monitor.currentAppName, "Safari")
        XCTAssertEqual(monitor.currentPID, 101)
        XCTAssertEqual(monitor.effectiveAppID, "com.apple.Safari")
    }

    func testIgnoredApplicationActivationKeepsBrowserContextForPreviousApp() {
        let monitor = AppMonitor(ignoredBundleIdentifiers: ["app.peyton.shorty"])

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 201
        )
        monitor.updateBrowserContext(domain: "www.figma.com", source: .safariExtension)

        XCTAssertFalse(monitor.updateActiveApplication(
            bundleIdentifier: "app.peyton.shorty",
            localizedName: "Shorty",
            processIdentifier: 202
        ))

        XCTAssertEqual(monitor.currentBundleID, "com.apple.Safari")
        XCTAssertEqual(monitor.webAppDomain, "figma.com")
        XCTAssertEqual(monitor.browserContextSource, .safariExtension)
        XCTAssertEqual(monitor.effectiveAppID, "web:figma.com")
    }

    func testRefreshActiveApplicationUsesInjectedFrontmostSnapshot() {
        let monitor = AppMonitor(ignoredBundleIdentifiers: ["app.peyton.shorty"])

        XCTAssertTrue(monitor.refreshActiveApplication(
            frontmostApplication: AppMonitor.ActiveApplicationSnapshot(
                bundleIdentifier: "com.apple.TextEdit",
                localizedName: "TextEdit",
                processIdentifier: 301
            )
        ))

        XCTAssertEqual(monitor.currentBundleID, "com.apple.TextEdit")
        XCTAssertEqual(monitor.currentAppName, "TextEdit")
        XCTAssertEqual(monitor.currentPID, 301)
    }

    func testRefreshActiveApplicationIgnoresTerminatedFrontmostSnapshot() {
        let monitor = AppMonitor(ignoredBundleIdentifiers: ["app.peyton.shorty"])

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit",
            processIdentifier: 401
        )

        XCTAssertFalse(monitor.refreshActiveApplication(
            frontmostApplication: AppMonitor.ActiveApplicationSnapshot(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 402,
                isTerminated: true
            )
        ))

        XCTAssertEqual(monitor.currentBundleID, "com.apple.TextEdit")
        XCTAssertEqual(monitor.currentPID, 401)
    }

    func testTerminatingCurrentApplicationClearsActiveContext() {
        let monitor = AppMonitor(ignoredBundleIdentifiers: ["app.peyton.shorty"])

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 501
        )
        monitor.updateBrowserContext(domain: "www.figma.com", source: .safariExtension)

        XCTAssertTrue(monitor.activeApplicationDidTerminate(
            AppMonitor.ActiveApplicationSnapshot(
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari",
                processIdentifier: 501,
                isTerminated: true
            )
        ))

        XCTAssertNil(monitor.currentBundleID)
        XCTAssertNil(monitor.currentAppName)
        XCTAssertEqual(monitor.currentPID, 0)
        XCTAssertNil(monitor.webAppDomain)
        XCTAssertEqual(monitor.browserContextSource, .none)
        XCTAssertNil(monitor.effectiveAppID)
    }

    func testTerminatingDifferentApplicationKeepsActiveContext() {
        let monitor = AppMonitor(ignoredBundleIdentifiers: ["app.peyton.shorty"])

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 601
        )

        XCTAssertFalse(monitor.activeApplicationDidTerminate(
            AppMonitor.ActiveApplicationSnapshot(
                bundleIdentifier: "com.apple.TextEdit",
                localizedName: "TextEdit",
                processIdentifier: 602,
                isTerminated: true
            )
        ))

        XCTAssertEqual(monitor.currentBundleID, "com.apple.Safari")
        XCTAssertEqual(monitor.currentPID, 601)
    }

    func testWebDomainIsOnlyEffectiveWhileBrowserIsActive() {
        let monitor = AppMonitor()

        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 101
        )
        monitor.updateBrowserContext(domain: "workspace.slack.com", source: .chromeBridge)

        XCTAssertEqual(monitor.effectiveAppID, "web:slack.com")
        XCTAssertEqual(monitor.browserContextSource, .chromeBridge)

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit",
            processIdentifier: 102
        )

        XCTAssertNil(monitor.webAppDomain)
        XCTAssertEqual(monitor.browserContextSource, .none)
        XCTAssertEqual(monitor.effectiveAppID, "com.apple.TextEdit")
    }

    func testSwitchingBrowsersClearsStaleWebDomain() {
        let monitor = AppMonitor()

        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 201
        )
        monitor.updateBrowserContext(domain: "slack.com", source: .chromeBridge)
        XCTAssertEqual(monitor.effectiveAppID, "web:slack.com")

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 202
        )

        XCTAssertNil(monitor.webAppDomain)
        XCTAssertEqual(monitor.browserContextSource, .none)
        XCTAssertEqual(monitor.effectiveAppID, "com.apple.Safari")
    }

    func testSameBrowserActivationKeepsDomainUntilBridgeReportsAnotherPage() {
        let monitor = AppMonitor()

        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 301
        )
        monitor.updateBrowserContext(domain: "figma.com", source: .chromeBridge)

        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 302
        )

        XCTAssertEqual(monitor.webAppDomain, "figma.com")
        XCTAssertEqual(monitor.browserContextSource, .chromeBridge)
        XCTAssertEqual(monitor.effectiveAppID, "web:figma.com")
    }

    func testSafariExtensionSourceCanDriveWebAdapterForSafari() {
        let monitor = AppMonitor()

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 401
        )
        monitor.updateBrowserContext(domain: "www.figma.com", source: .safariExtension)

        XCTAssertEqual(monitor.browserContextSource, .safariExtension)
        XCTAssertEqual(monitor.webAppDomain, "figma.com")
        XCTAssertEqual(monitor.effectiveAppID, "web:figma.com")
    }
}
