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
