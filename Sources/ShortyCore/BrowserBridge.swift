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
/// For the MVP, we use a simpler approach: a named pipe (FIFO) that
/// the native messaging shim writes to.
public final class BrowserBridge {

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
        self.socketPath = NSTemporaryDirectory() + "shorty-bridge.sock"
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
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBuf = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strncpy(pathBuf, ptr, MemoryLayout.size(ofValue: addr.sun_path) - 1)
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
                self?.handleClient(fd: clientFD)
            }
        }
    }

    // MARK: - Client handler

    private func handleClient(fd: Int32) {
        defer { close(fd) }

        // Read loop: Chrome native messaging format
        // (4-byte LE length prefix + JSON payload)
        while isListening {
            // Read 4-byte length
            var lengthBytes = [UInt8](repeating: 0, count: 4)
            let lenRead = read(fd, &lengthBytes, 4)
            guard lenRead == 4 else { return }

            let length = UInt32(lengthBytes[0])
                       | UInt32(lengthBytes[1]) << 8
                       | UInt32(lengthBytes[2]) << 16
                       | UInt32(lengthBytes[3]) << 24

            guard length > 0, length < 1_000_000 else { return } // sanity

            // Read payload
            var payload = [UInt8](repeating: 0, count: Int(length))
            var totalRead = 0
            while totalRead < Int(length) {
                let n = read(fd, &payload + totalRead, Int(length) - totalRead)
                guard n > 0 else { return }
                totalRead += n
            }

            // Parse JSON
            guard let json = try? JSONSerialization.jsonObject(
                with: Data(payload)
            ) as? [String: Any] else { continue }

            if let type = json["type"] as? String,
               type == "domain_changed",
               let domain = json["domain"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.appMonitor?.webAppDomain = domain
                }
            }

            // Send ack
            let ack = #"{"type":"ack"}"#
            let ackData = Array(ack.utf8)
            var ackLen = UInt32(ackData.count).littleEndian
            withUnsafeBytes(of: &ackLen) { buf in
                _ = write(fd, buf.baseAddress!, 4)
            }
            _ = ackData.withUnsafeBufferPointer { buf in
                write(fd, buf.baseAddress!, ackData.count)
            }
        }
    }
}
