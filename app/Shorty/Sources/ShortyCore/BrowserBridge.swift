import Foundation

/// Phase 3: Native Messaging host that communicates with the Shorty
/// browser extension to identify which web app the user is viewing.
///
/// ## Protocol
///
/// Chrome Native Messaging uses length-prefixed JSON over stdin/stdout:
///   - 4 bytes: message length as little-endian uint32
///   - N bytes: UTF-8 JSON payload
///
/// Inbound messages (from extension):
///   `{ "type": "domain_changed", "domain": "slack.com" }`
///
/// Outbound messages (to extension):
///   `{ "type": "ack" }`
///
/// ## Architecture
///
/// The BrowserBridge doesn't run as a separate process — it's a
/// lightweight server that listens on a Unix domain socket. The actual
/// native messaging host (`shorty-bridge`) is a tiny shim that reads
/// Chrome's stdin protocol and forwards to this socket.
///
/// For the MVP, the shim connects to a local Unix domain socket and
/// forwards Chrome's length-prefixed messages without interpretation.
public final class BrowserBridge {
    public enum NativeMessage: Equatable {
        case domainChanged(String)
    }

    public static let socketName = "shorty-bridge.sock"
    public static let maxMessageLength: UInt32 = 1_000_000

    public static var defaultSocketPath: String {
        NSTemporaryDirectory() + socketName
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

    public static func decodeMessagePayload(_ payload: Data) -> NativeMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = json["type"] as? String,
              type == "domain_changed",
              let domain = json["domain"] as? String,
              !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return .domainChanged(DomainNormalizer.normalizedDomain(for: domain))
    }

    /// Reference to the app monitor — we update its `webAppDomain`.
    private weak var appMonitor: AppMonitor?

    /// Path to the Unix domain socket.
    private let socketPath: String

    /// Background thread for the listener.
    private var listenerThread: Thread?
    private var isListening = false

    /// File descriptor for the socket.
    private var serverFD: Int32 = -1

    public init(appMonitor: AppMonitor) {
        self.appMonitor = appMonitor
        self.socketPath = Self.defaultSocketPath
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    /// Start listening for connections from the native messaging shim.
    public func start() {
        guard !isListening else { return }

        // Clean up stale socket
        unlink(socketPath)

        // Create Unix domain socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            print("[BrowserBridge] Failed to create socket: \(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let socketPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        socketPath.withCString { ptr in
            withUnsafeMutableBytes(of: &addr.sun_path) { pathBytes in
                guard let pathBuf = pathBytes.baseAddress?
                        .assumingMemoryBound(to: CChar.self) else {
                    return
                }
                strncpy(pathBuf, ptr, socketPathCapacity - 1)
                pathBuf[socketPathCapacity - 1] = 0
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            print("[BrowserBridge] Failed to bind: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        guard listen(serverFD, 5) == 0 else {
            print("[BrowserBridge] Failed to listen: \(errno)")
            close(serverFD)
            serverFD = -1
            return
        }

        isListening = true

        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "com.shorty.browser-bridge"
        thread.qualityOfService = .utility
        listenerThread = thread
        thread.start()
    }

    /// Stop the listener and clean up.
    public func stop() {
        isListening = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
        listenerThread = nil
    }

    // MARK: - Accept loop

    private func acceptLoop() {
        while isListening {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(serverFD, sockPtr, &clientLen)
                }
            }

            guard clientFD >= 0 else {
                if isListening {
                    usleep(100_000) // 100ms backoff on error
                }
                continue
            }

            // Handle this client on a background queue
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleClient(fileDescriptor: clientFD)
            }
        }
    }

    // MARK: - Client handler

    private func handleClient(fileDescriptor: Int32) {
        defer { close(fileDescriptor) }

        // Read loop: Chrome native messaging format
        // (4-byte LE length prefix + JSON payload)
        while isListening {
            // Read 4-byte length
            var lengthBytes = [UInt8](repeating: 0, count: 4)
            let lenRead = lengthBytes.withUnsafeMutableBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return -1 }
                return read(fileDescriptor, baseAddress, 4)
            }
            guard lenRead == 4 else { return }

            guard let length = Self.messageLength(from: lengthBytes) else { return }

            // Read payload
            var payload = [UInt8](repeating: 0, count: Int(length))
            var totalRead = 0
            while totalRead < Int(length) {
                let bytesRead = payload.withUnsafeMutableBytes { buffer in
                    guard let baseAddress = buffer.baseAddress else { return -1 }
                    return read(
                        fileDescriptor,
                        baseAddress.advanced(by: totalRead),
                        Int(length) - totalRead
                    )
                }
                guard bytesRead > 0 else { return }
                totalRead += bytesRead
            }

            if let message = Self.decodeMessagePayload(Data(payload)),
               case .domainChanged(let domain) = message {
                DispatchQueue.main.async { [weak self] in
                    self?.appMonitor?.webAppDomain = domain
                }
            }

            sendAck(to: fileDescriptor)
        }
    }

    private func sendAck(to fileDescriptor: Int32) {
        let ack = #"{"type":"ack"}"#
        let ackData = Array(ack.utf8)
        var ackLen = UInt32(ackData.count).littleEndian
        withUnsafeBytes(of: &ackLen) { buf in
            guard let baseAddress = buf.baseAddress else { return }
            _ = write(fileDescriptor, baseAddress, 4)
        }
        _ = ackData.withUnsafeBufferPointer { buf in
            write(fileDescriptor, buf.baseAddress!, ackData.count)
        }
    }
}
