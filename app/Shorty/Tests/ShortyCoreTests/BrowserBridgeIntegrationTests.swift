import Darwin
import Foundation
import XCTest
@testable import ShortyCore

final class BrowserBridgeIntegrationTests: XCTestCase {

    func testBridgeAcceptsSupportedDomainOverUnixSocket() throws {
        let monitor = browserBackedMonitor()
        let socketPath = temporarySocketPath()
        let bridge = BrowserBridge(appMonitor: monitor, socketPath: socketPath)
        bridge.start()
        defer { bridge.stop() }

        XCTAssertTrue(waitFor(FileManager.default.fileExists(atPath: socketPath)))

        let socket = try connectUnixSocket(to: socketPath)
        defer { close(socket) }

        try sendNativeMessage(
            #"{"type":"domain_changed","domain":"workspace.slack.com"}"#,
            to: socket,
            splitAfterBytes: 2
        )
        let ack = try readNativeMessage(from: socket)

        XCTAssertEqual(ack, #"{"type":"ack"}"#)
        XCTAssertTrue(waitFor(monitor.webAppDomain == "slack.com"))
        XCTAssertEqual(monitor.browserContextSource, .chromeBridge)
        XCTAssertEqual(monitor.effectiveAppID, "web:slack.com")
        XCTAssertEqual(bridge.status, .connected("slack.com"))
    }

    func testBridgeClearsDomainOverUnixSocket() throws {
        let monitor = browserBackedMonitor()
        let socketPath = temporarySocketPath()
        let bridge = BrowserBridge(appMonitor: monitor, socketPath: socketPath)
        bridge.start()
        defer { bridge.stop() }

        XCTAssertTrue(waitFor(FileManager.default.fileExists(atPath: socketPath)))

        let socket = try connectUnixSocket(to: socketPath)
        defer { close(socket) }

        try sendNativeMessage(
            #"{"type":"domain_changed","domain":"figma.com"}"#,
            to: socket
        )
        _ = try readNativeMessage(from: socket)
        XCTAssertTrue(waitFor(monitor.webAppDomain == "figma.com"))

        try sendNativeMessage(#"{"type":"domain_cleared"}"#, to: socket)
        let ack = try readNativeMessage(from: socket)

        XCTAssertEqual(ack, #"{"type":"ack"}"#)
        XCTAssertTrue(waitFor(monitor.webAppDomain == nil))
        XCTAssertEqual(monitor.browserContextSource, .none)
        XCTAssertEqual(monitor.effectiveAppID, "com.google.Chrome")
        XCTAssertEqual(bridge.status, .listening(socketPath))
    }

    func testBridgeIgnoresUnsupportedDomainButAcknowledgesMessage() throws {
        let monitor = browserBackedMonitor()
        let socketPath = temporarySocketPath()
        let bridge = BrowserBridge(appMonitor: monitor, socketPath: socketPath)
        bridge.start()
        defer { bridge.stop() }

        XCTAssertTrue(waitFor(FileManager.default.fileExists(atPath: socketPath)))

        let socket = try connectUnixSocket(to: socketPath)
        defer { close(socket) }

        try sendNativeMessage(
            #"{"type":"domain_changed","domain":"example.com"}"#,
            to: socket
        )
        let ack = try readNativeMessage(from: socket)

        XCTAssertEqual(ack, #"{"type":"ack"}"#)
        XCTAssertNil(monitor.webAppDomain)
        XCTAssertEqual(monitor.effectiveAppID, "com.google.Chrome")
    }

    func testBridgeDecodeSupportsClearMessage() {
        let payload = Data(#"{"type":"domain_cleared"}"#.utf8)

        XCTAssertEqual(BrowserBridge.decodeMessagePayload(payload), .domainCleared)
    }

    private func browserBackedMonitor() -> AppMonitor {
        let monitor = AppMonitor()
        monitor.updateActiveApplication(
            bundleIdentifier: "com.google.Chrome",
            localizedName: "Google Chrome",
            processIdentifier: 401
        )
        return monitor
    }

    private func temporarySocketPath() -> String {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("shorty-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("shorty-bridge.sock")
            .path
    }

    private func connectUnixSocket(to path: String) throws -> Int32 {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fileDescriptor, 0)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        try copy(path, into: &address)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketPointer in
                connect(
                    fileDescriptor,
                    socketPointer,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }

        if result != 0 {
            close(fileDescriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return fileDescriptor
    }

    private func copy(_ path: String, into address: inout sockaddr_un) throws {
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            throw POSIXError(.ENAMETOOLONG)
        }

        path.withCString { pointer in
            withUnsafeMutableBytes(of: &address.sun_path) { pathBytes in
                guard let pathBuffer = pathBytes.baseAddress?
                    .assumingMemoryBound(to: CChar.self) else {
                    return
                }
                strncpy(pathBuffer, pointer, capacity - 1)
                pathBuffer[capacity - 1] = 0
            }
        }
    }

    private func sendNativeMessage(
        _ json: String,
        to fileDescriptor: Int32,
        splitAfterBytes: Int? = nil
    ) throws {
        let frame = nativeFrame(json)
        if let splitAfterBytes {
            let prefix = Data(frame.prefix(splitAfterBytes))
            let suffix = Data(frame.dropFirst(splitAfterBytes))
            XCTAssertEqual(writeData(prefix, to: fileDescriptor), prefix.count)
            XCTAssertTrue(BrowserBridge.writeAll(suffix, to: fileDescriptor))
        } else {
            XCTAssertTrue(BrowserBridge.writeAll(frame, to: fileDescriptor))
        }
    }

    private func readNativeMessage(from fileDescriptor: Int32) throws -> String {
        let lengthData = try XCTUnwrap(
            BrowserBridge.readExactly(from: fileDescriptor, count: 4)
        )
        let length = try XCTUnwrap(
            BrowserBridge.messageLength(from: Array(lengthData))
        )
        let payload = try XCTUnwrap(
            BrowserBridge.readExactly(from: fileDescriptor, count: Int(length))
        )
        return try XCTUnwrap(String(data: payload, encoding: .utf8))
    }

    private func nativeFrame(_ json: String) -> Data {
        let payload = Data(json.utf8)
        var length = UInt32(payload.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(payload)
        return frame
    }

    private func writeData(_ data: Data, to fileDescriptor: Int32) -> Int {
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            return write(fileDescriptor, baseAddress, data.count)
        }
    }

    private func waitFor(
        _ condition: @autoclosure () -> Bool,
        timeout: TimeInterval = 2
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}
