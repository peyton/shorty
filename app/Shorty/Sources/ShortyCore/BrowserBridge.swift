import Combine
import Darwin
import Foundation

/// Native Messaging socket server used by the optional browser extension.
///
/// Chrome-family browsers speak length-prefixed JSON to the `ShortyBridge`
/// command-line target. That target forwards the same frames to this Unix
/// domain socket so the app can update `AppMonitor.webAppDomain`.
public final class BrowserBridge: ObservableObject {
    public struct MessageMetadata: Equatable, Codable {
        public let protocolVersion: Int
        public let source: String?
        public let tabID: Int?
        public let windowID: Int?
        public let title: String?

        public init(
            protocolVersion: Int = 1,
            source: String? = nil,
            tabID: Int? = nil,
            windowID: Int? = nil,
            title: String? = nil
        ) {
            self.protocolVersion = protocolVersion
            self.source = source
            self.tabID = tabID
            self.windowID = windowID
            self.title = title
        }
    }

    public enum NativeMessage: Equatable {
        case domainChanged(String, MessageMetadata)
        case domainCleared
    }

    public static let socketName = "shorty-bridge.sock"
    public static let maxMessageLength: UInt32 = 64 * 1024

    public static var defaultSocketPath: String {
        applicationSupportDirectory()
            .appendingPathComponent(socketName)
            .path
    }

    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return appSupport
            .appendingPathComponent("Shorty", isDirectory: true)
            .appendingPathComponent("Bridge", isDirectory: true)
    }

    public static func messageLength(from lengthBytes: [UInt8]) -> UInt32? {
        guard lengthBytes.count == 4 else {
            return nil
        }

        let length = UInt32(lengthBytes[0])
            | UInt32(lengthBytes[1]) << 8
            | UInt32(lengthBytes[2]) << 16
            | UInt32(lengthBytes[3]) << 24

        guard length > 0, length <= maxMessageLength else {
            return nil
        }

        return length
    }

    public static func decodeMessagePayload(
        _ payload: Data,
        reportAllDomains: Bool = false
    ) -> NativeMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = json["type"] as? String
        else {
            return nil
        }

        if type == "domain_cleared" {
            return .domainCleared
        }

        guard type == "domain_changed",
              let rawDomain = json["domain"] as? String,
              !rawDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let normalized = DomainNormalizer.normalizedDomain(for: rawDomain)
        guard reportAllDomains || DomainNormalizer.supportedWebAppDomains.contains(normalized) else {
            return .domainCleared
        }

        let metadata = MessageMetadata(
            protocolVersion: json["protocol_version"] as? Int ?? 1,
            source: json["source"] as? String,
            tabID: json["tab_id"] as? Int,
            windowID: json["window_id"] as? Int,
            title: json["title"] as? String
        )
        return .domainChanged(normalized, metadata)
    }

    public static func readExactly(
        from fileDescriptor: Int32,
        count: Int,
        timeoutMilliseconds: Int32 = 30_000
    ) -> Data? {
        var data = Data(count: count)
        var totalRead = 0

        while totalRead < count {
            guard waitForReadable(
                fileDescriptor: fileDescriptor,
                timeoutMilliseconds: timeoutMilliseconds
            ) else {
                return nil
            }

            let bytesRead = data.withUnsafeMutableBytes { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return -1
                }
                return read(
                    fileDescriptor,
                    baseAddress.advanced(by: totalRead),
                    count - totalRead
                )
            }

            if bytesRead == 0 {
                return nil
            }
            if bytesRead < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }

            totalRead += bytesRead
        }

        return data
    }

    private static func waitForReadable(
        fileDescriptor: Int32,
        timeoutMilliseconds: Int32
    ) -> Bool {
        var pollDescriptor = pollfd(
            fd: fileDescriptor,
            events: Int16(POLLIN),
            revents: 0
        )

        while true {
            let result = poll(&pollDescriptor, 1, timeoutMilliseconds)
            if result > 0 {
                return pollDescriptor.revents & Int16(POLLIN) != 0
                    || pollDescriptor.revents & Int16(POLLHUP) != 0
            }
            if result == 0 {
                return false
            }
            if errno == EINTR {
                continue
            }
            return false
        }
    }

    public static func writeAll(_ data: Data, to fileDescriptor: Int32) -> Bool {
        var totalWritten = 0

        while totalWritten < data.count {
            let bytesWritten = data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else {
                    return -1
                }
                return write(
                    fileDescriptor,
                    baseAddress.advanced(by: totalWritten),
                    data.count - totalWritten
                )
            }

            if bytesWritten < 0, errno == EINTR {
                continue
            }
            if bytesWritten <= 0 {
                return false
            }

            totalWritten += bytesWritten
        }

        return true
    }

    @Published public private(set) var status: BrowserBridgeStatus = .stopped

    private weak var appMonitor: AppMonitor?
    private let socketPath: String
    private let configuration: EngineConfiguration
    private let fileManager: FileManager

    private var listenerThread: Thread?
    private var isListening = false
    private var serverFD: Int32 = -1
    private var lastDomain: String?
    private let stateLock = NSLock()
    private let domainLock = NSLock()

    public var currentSocketPath: String {
        socketPath
    }

    public init(
        appMonitor: AppMonitor,
        configuration: EngineConfiguration = .releaseDefault,
        fileManager: FileManager = .default,
        socketPath: String? = nil
    ) {
        self.appMonitor = appMonitor
        self.configuration = configuration
        self.fileManager = fileManager
        self.socketPath = socketPath ?? Self.defaultSocketPath
    }

    deinit {
        stop()
    }

    public func start() {
        guard !currentIsListening else { return }

        do {
            try prepareSocketDirectory()
        } catch {
            setStatus(.failed("Could not prepare browser bridge directory: \(error.localizedDescription)"))
            ShortyLog.browserBridge.error("Failed to prepare socket directory: \(error.localizedDescription)")
            return
        }

        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            setStatus(.failed("Could not create browser bridge socket."))
            ShortyLog.browserBridge.error("Failed to create socket: \(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard copySocketPath(socketPath, into: &addr) else {
            close(serverFD)
            serverFD = -1
            setStatus(.failed("Browser bridge socket path is too long."))
            return
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let message = "Could not bind browser bridge socket."
            ShortyLog.browserBridge.error("\(message) errno=\(errno)")
            close(serverFD)
            serverFD = -1
            setStatus(.failed(message))
            return
        }

        guard listen(serverFD, 5) == 0 else {
            let message = "Could not listen for browser bridge connections."
            ShortyLog.browserBridge.error("\(message) errno=\(errno)")
            close(serverFD)
            serverFD = -1
            setStatus(.failed(message))
            return
        }

        setListening(true)
        setStatus(.listening(socketPath))

        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "com.shorty.browser-bridge"
        thread.qualityOfService = .utility
        listenerThread = thread
        thread.start()
    }

    public func stop() {
        setListening(false)
        stateLock.lock()
        let socketDescriptor = serverFD
        serverFD = -1
        stateLock.unlock()
        if socketDescriptor >= 0 {
            close(socketDescriptor)
        }
        unlink(socketPath)
        listenerThread = nil
        setStatus(.stopped)
    }

    private func prepareSocketDirectory() throws {
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: directory.path
        )
    }

    private func copySocketPath(_ path: String, into address: inout sockaddr_un) -> Bool {
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            return false
        }

        path.withCString { ptr in
            withUnsafeMutableBytes(of: &address.sun_path) { pathBytes in
                guard let pathBuffer = pathBytes.baseAddress?
                    .assumingMemoryBound(to: CChar.self) else {
                    return
                }
                strncpy(pathBuffer, ptr, capacity - 1)
                pathBuffer[capacity - 1] = 0
            }
        }
        return true
    }

    private func acceptLoop() {
        while currentIsListening {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let serverDescriptor = currentServerFD

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverDescriptor, sockPtr, &clientLen)
                }
            }

            guard clientFD >= 0 else {
                if errno == EINTR {
                    continue
                }
                if currentIsListening {
                    ShortyLog.browserBridge.warning("accept failed: \(errno)")
                    usleep(100_000)
                }
                continue
            }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleClient(fileDescriptor: clientFD)
            }
        }
    }

    private func handleClient(fileDescriptor: Int32) {
        defer { close(fileDescriptor) }

        while currentIsListening {
            guard let lengthData = Self.readExactly(from: fileDescriptor, count: 4) else {
                return
            }
            guard let length = Self.messageLength(from: Array(lengthData)) else {
                ShortyLog.browserBridge.warning("Rejected invalid native message length")
                return
            }
            guard let payload = Self.readExactly(from: fileDescriptor, count: Int(length)) else {
                return
            }

            if let message = Self.decodeMessagePayload(
                payload,
                reportAllDomains: configuration.reportAllBrowserDomains
            ) {
                switch message {
                case .domainChanged(let domain, let metadata):
                    setDomain(domain, metadata: metadata)
                case .domainCleared:
                    clearDomain()
                }
            }

            guard sendAck(to: fileDescriptor) else {
                setStatus(.failed("Could not acknowledge browser bridge message."))
                return
            }
        }
    }

    private func setDomain(_ domain: String, metadata: MessageMetadata) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.updateLastDomainIfChanged(domain) else { return }
            self.appMonitor?.updateBrowserContext(domain: domain, source: .chromeBridge)
            self.status = .connected(domain)
            ShortyLog.browserBridge.debug(
                "Domain \(domain) protocol=\(metadata.protocolVersion) tab=\(metadata.tabID ?? -1) window=\(metadata.windowID ?? -1)"
            )
        }
    }

    private func clearDomain() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setLastDomain(nil)
            self.appMonitor?.clearBrowserContext(source: .chromeBridge)
            if self.currentIsListening {
                self.status = .listening(self.socketPath)
            }
        }
    }

    private func updateLastDomainIfChanged(_ domain: String) -> Bool {
        domainLock.lock()
        defer { domainLock.unlock() }
        guard lastDomain != domain else { return false }
        lastDomain = domain
        return true
    }

    private func setLastDomain(_ domain: String?) {
        domainLock.lock()
        lastDomain = domain
        domainLock.unlock()
    }

    private func sendAck(to fileDescriptor: Int32) -> Bool {
        let ack = Data(#"{"type":"ack"}"#.utf8)
        var ackLength = UInt32(ack.count).littleEndian
        let lengthData = Data(bytes: &ackLength, count: 4)
        return Self.writeAll(lengthData + ack, to: fileDescriptor)
    }

    private func setStatus(_ newStatus: BrowserBridgeStatus) {
        if Thread.isMainThread {
            status = newStatus
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.status = newStatus
            }
        }
    }

    private var currentIsListening: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isListening
    }

    private var currentServerFD: Int32 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return serverFD
    }

    private func setListening(_ listening: Bool) {
        stateLock.lock()
        isListening = listening
        stateLock.unlock()
    }
}
