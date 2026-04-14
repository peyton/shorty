import Darwin
import Foundation
import ShortyCore

private enum BridgeExit: Error {
    case cannotConnect
    case invalidLength
    case socketClosed
}

private func readExactly(from fileDescriptor: Int32, count: Int) -> Data? {
    var data = Data(count: count)
    var totalRead = 0

    while totalRead < count {
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
            return nil
        }

        totalRead += bytesRead
    }

    return data
}

private func writeAll(_ data: Data, to fileDescriptor: Int32) -> Bool {
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

        if bytesWritten <= 0 {
            return false
        }

        totalWritten += bytesWritten
    }

    return true
}

private func connectToShorty() throws -> Int32 {
    let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else {
        throw BridgeExit.cannotConnect
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let socketPath = BrowserBridge.defaultSocketPath
    let socketPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
    socketPath.withCString { ptr in
        withUnsafeMutableBytes(of: &addr.sun_path) { pathBytes in
            guard let pathBuffer = pathBytes.baseAddress?
                    .assumingMemoryBound(to: CChar.self) else {
                return
            }
            strncpy(pathBuffer, ptr, socketPathCapacity - 1)
            pathBuffer[socketPathCapacity - 1] = 0
        }
    }

    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(
                fileDescriptor,
                sockPtr,
                socklen_t(MemoryLayout<sockaddr_un>.size)
            )
        }
    }

    guard result == 0 else {
        close(fileDescriptor)
        throw BridgeExit.cannotConnect
    }

    return fileDescriptor
}

private func writeNativeMessage(_ json: String) {
    let payload = Data(json.utf8)
    var length = UInt32(payload.count).littleEndian
    let lengthData = Data(bytes: &length, count: 4)
    _ = writeAll(lengthData + payload, to: STDOUT_FILENO)
}

private func forwardNextMessage() throws -> Bool {
    guard let lengthData = readExactly(from: STDIN_FILENO, count: 4) else {
        return false
    }

    guard let length = BrowserBridge.messageLength(from: Array(lengthData)) else {
        throw BridgeExit.invalidLength
    }

    guard let payload = readExactly(from: STDIN_FILENO, count: Int(length)) else {
        throw BridgeExit.socketClosed
    }

    var frame = lengthData
    frame.append(payload)

    let socket = try connectToShorty()
    defer { close(socket) }

    guard writeAll(frame, to: socket),
          let ackLengthData = readExactly(from: socket, count: 4),
          let ackLength = BrowserBridge.messageLength(from: Array(ackLengthData)),
          let ackPayload = readExactly(from: socket, count: Int(ackLength))
    else {
        throw BridgeExit.socketClosed
    }

    var ackFrame = ackLengthData
    ackFrame.append(ackPayload)
    guard writeAll(ackFrame, to: STDOUT_FILENO) else {
        throw BridgeExit.socketClosed
    }

    return true
}

do {
    while try forwardNextMessage() {}
} catch BridgeExit.cannotConnect {
    writeNativeMessage(#"{"type":"error","message":"Shorty is not running"}"#)
    exit(1)
} catch {
    writeNativeMessage(#"{"type":"error","message":"Shorty bridge failed"}"#)
    exit(1)
}
