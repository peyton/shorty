import XCTest
@testable import ShortyCore

final class AppMonitorIntegrationTests: XCTestCase {

    func testWebDomainIsOnlyEffectiveWhileBrowserIsActive() {
        let monitor = AppMonitor()

        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 101
        )
        monitor.webAppDomain = "workspace.slack.com"

        XCTAssertEqual(monitor.effectiveAppID, "web:slack.com")

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.TextEdit",
            localizedName: "TextEdit",
            processIdentifier: 102
        )

        XCTAssertNil(monitor.webAppDomain)
        XCTAssertEqual(monitor.effectiveAppID, "com.apple.TextEdit")
    }

    func testSwitchingBrowsersClearsStaleWebDomain() {
        let monitor = AppMonitor()

        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 201
        )
        monitor.webAppDomain = "slack.com"
        XCTAssertEqual(monitor.effectiveAppID, "web:slack.com")

        monitor.updateActiveApplication(
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            processIdentifier: 202
        )

        XCTAssertNil(monitor.webAppDomain)
        XCTAssertEqual(monitor.effectiveAppID, "com.apple.Safari")
    }

    func testSameBrowserActivationKeepsDomainUntilBridgeReportsAnotherPage() {
        let monitor = AppMonitor()

        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 301
        )
        monitor.webAppDomain = "figma.com"

        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 302
        )

        XCTAssertEqual(monitor.webAppDomain, "figma.com")
        XCTAssertEqual(monitor.effectiveAppID, "web:figma.com")
    }
}
