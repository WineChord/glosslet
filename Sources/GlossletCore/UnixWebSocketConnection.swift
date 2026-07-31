import CryptoKit
import Darwin
import Foundation

final class UnixWebSocketConnection: @unchecked Sendable {
    typealias TextHandler = @Sendable (Data) -> Void
    typealias CloseHandler = @Sendable (Error?) -> Void

    private static let websocketMagicGUID =
        "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    private static let maximumMessageBytes = 64 * 1_024 * 1_024

    private let socketPath: String
    private let onText: TextHandler
    private let onClose: CloseHandler
    private let queue = DispatchQueue(
        label: "com.winechord.glosslet.codex-unix-websocket"
    )

    private var descriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var receiveBuffer = Data()
    private var fragmentedMessage = Data()
    private var fragmentedOpcode: UInt8?
    private var didNotifyClose = false

    init(
        socketPath: String,
        onText: @escaping TextHandler,
        onClose: @escaping CloseHandler
    ) {
        self.socketPath = socketPath
        self.onText = onText
        self.onClose = onClose
    }

    deinit {
        readSource?.cancel()
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try connectSynchronously()
                    continuation.resume()
                } catch {
                    closeSynchronously(notifying: false, error: nil)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func send(text data: Data) throws {
        try queue.sync { [self] in
            guard descriptor >= 0 else {
                throw UnixWebSocketError.closed
            }
            try writeFrame(opcode: 0x1, payload: data)
        }
    }

    func close() {
        queue.async { [self] in
            closeSynchronously(notifying: false, error: nil)
        }
    }

    private func connectSynchronously() throws {
        guard descriptor < 0 else {
            return
        }

        let socketDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw UnixWebSocketError.systemCall(
                operation: "socket",
                code: errno
            )
        }
        descriptor = socketDescriptor

        var noSigPipe: Int32 = 1
        guard
            setsockopt(
                socketDescriptor,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout.size(ofValue: noSigPipe))
            ) == 0
        else {
            throw UnixWebSocketError.systemCall(
                operation: "setsockopt",
                code: errno
            )
        }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        let timeoutSize = socklen_t(MemoryLayout<timeval>.size)
        _ = withUnsafePointer(to: &timeout) { pointer in
            setsockopt(
                socketDescriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                timeoutSize
            )
        }
        _ = withUnsafePointer(to: &timeout) { pointer in
            setsockopt(
                socketDescriptor,
                SOL_SOCKET,
                SO_SNDTIMEO,
                pointer,
                timeoutSize
            )
        }

        try connectUnixSocket(socketDescriptor)
        try performWebSocketHandshake(socketDescriptor)

        timeout = timeval(tv_sec: 0, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) { pointer in
            setsockopt(
                socketDescriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                timeoutSize
            )
        }
        _ = withUnsafePointer(to: &timeout) { pointer in
            setsockopt(
                socketDescriptor,
                SOL_SOCKET,
                SO_SNDTIMEO,
                pointer,
                timeoutSize
            )
        }

        let source = DispatchSource.makeReadSource(
            fileDescriptor: socketDescriptor,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.readAvailableBytes()
        }
        source.setCancelHandler {}
        readSource = source
        source.resume()

        if !receiveBuffer.isEmpty {
            processFrames()
        }
    }

    private func connectUnixSocket(_ socketDescriptor: Int32) throws {
        var address = sockaddr_un()
        let pathBytes = socketPath.utf8CString
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= pathCapacity else {
            throw UnixWebSocketError.socketPathTooLong(socketPath)
        }

        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: pathCapacity
            ) { destination in
                for (index, byte) in pathBytes.enumerated() {
                    destination[index] = byte
                }
            }
        }

        let pathOffset =
            MemoryLayout<sockaddr_un>.offset(
                of: \sockaddr_un.sun_path
            ) ?? 2
        let addressLength = socklen_t(pathOffset + pathBytes.count)
        address.sun_len = UInt8(addressLength)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(
                to: sockaddr.self,
                capacity: 1
            ) { addressPointer in
                Darwin.connect(
                    socketDescriptor,
                    addressPointer,
                    addressLength
                )
            }
        }
        guard result == 0 else {
            throw UnixWebSocketError.systemCall(
                operation: "connect",
                code: errno
            )
        }
    }

    private func performWebSocketHandshake(
        _ socketDescriptor: Int32
    ) throws {
        let nonce = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            .base64EncodedString()
        let request = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(nonce)",
            "Sec-WebSocket-Version: 13",
            "",
            "",
        ].joined(separator: "\r\n")
        try writeAll(Data(request.utf8), to: socketDescriptor)

        let separator = Data("\r\n\r\n".utf8)
        var response = Data()
        while response.range(of: separator) == nil {
            var bytes = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(
                socketDescriptor,
                &bytes,
                bytes.count
            )
            guard count > 0 else {
                throw UnixWebSocketError.invalidHandshake(
                    "Codex closed the control socket during the handshake."
                )
            }
            response.append(bytes, count: count)
            guard response.count <= 64 * 1_024 else {
                throw UnixWebSocketError.invalidHandshake(
                    "The control-socket handshake was too large."
                )
            }
        }

        guard let headerRange = response.range(of: separator) else {
            throw UnixWebSocketError.invalidHandshake(
                "Codex returned an incomplete control-socket handshake."
            )
        }
        let headerData = response[..<headerRange.lowerBound]
        receiveBuffer.append(response[headerRange.upperBound...])
        guard let headers = String(data: headerData, encoding: .utf8) else {
            throw UnixWebSocketError.invalidHandshake(
                "Codex returned non-text handshake headers."
            )
        }

        let lines = headers.components(separatedBy: "\r\n")
        guard lines.first?.contains(" 101 ") == true else {
            throw UnixWebSocketError.invalidHandshake(
                lines.first ?? "Codex rejected the control-socket handshake."
            )
        }
        let acceptHeader = lines.dropFirst().first { line in
            line.lowercased().hasPrefix("sec-websocket-accept:")
        }?.split(separator: ":", maxSplits: 1).last?
        .trimmingCharacters(in: .whitespaces)
        let digest = Insecure.SHA1.hash(
            data: Data((nonce + Self.websocketMagicGUID).utf8)
        )
        let expectedAccept = Data(digest).base64EncodedString()
        guard acceptHeader == expectedAccept else {
            throw UnixWebSocketError.invalidHandshake(
                "Codex returned an invalid WebSocket accept header."
            )
        }
    }

    private func readAvailableBytes() {
        guard descriptor >= 0 else {
            return
        }
        var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
        let count = Darwin.read(descriptor, &bytes, bytes.count)
        if count > 0 {
            receiveBuffer.append(bytes, count: count)
            processFrames()
            return
        }
        if count == 0 {
            closeSynchronously(
                notifying: true,
                error: UnixWebSocketError.closed
            )
            return
        }
        guard errno != EINTR && errno != EAGAIN else {
            return
        }
        closeSynchronously(
            notifying: true,
            error: UnixWebSocketError.systemCall(
                operation: "read",
                code: errno
            )
        )
    }

    private func processFrames() {
        while true {
            guard receiveBuffer.count >= 2 else {
                return
            }
            let first = receiveBuffer[receiveBuffer.startIndex]
            let second = receiveBuffer[receiveBuffer.startIndex + 1]
            let isFinal = first & 0x80 != 0
            let opcode = first & 0x0F
            let isMasked = second & 0x80 != 0
            var payloadLength = Int(second & 0x7F)
            var offset = 2

            if payloadLength == 126 {
                guard receiveBuffer.count >= offset + 2 else {
                    return
                }
                payloadLength =
                    receiveBuffer
                    .subdata(in: offset..<(offset + 2))
                    .reduce(0) { ($0 << 8) | Int($1) }
                offset += 2
            } else if payloadLength == 127 {
                guard receiveBuffer.count >= offset + 8 else {
                    return
                }
                let length =
                    receiveBuffer
                    .subdata(in: offset..<(offset + 8))
                    .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                guard length <= UInt64(Self.maximumMessageBytes) else {
                    closeSynchronously(
                        notifying: true,
                        error: UnixWebSocketError.messageTooLarge
                    )
                    return
                }
                payloadLength = Int(length)
                offset += 8
            }

            var mask: [UInt8] = []
            if isMasked {
                guard receiveBuffer.count >= offset + 4 else {
                    return
                }
                mask = Array(receiveBuffer[offset..<(offset + 4)])
                offset += 4
            }
            guard payloadLength <= Self.maximumMessageBytes else {
                closeSynchronously(
                    notifying: true,
                    error: UnixWebSocketError.messageTooLarge
                )
                return
            }
            guard receiveBuffer.count >= offset + payloadLength else {
                return
            }

            var payload = Data(
                receiveBuffer[offset..<(offset + payloadLength)]
            )
            receiveBuffer.removeSubrange(
                receiveBuffer.startIndex..<(offset + payloadLength)
            )
            if isMasked {
                payload = Data(
                    payload.enumerated().map { index, byte in
                        byte ^ mask[index % 4]
                    })
            }
            handleFrame(opcode: opcode, isFinal: isFinal, payload: payload)
            guard descriptor >= 0 else {
                return
            }
        }
    }

    private func handleFrame(
        opcode: UInt8,
        isFinal: Bool,
        payload: Data
    ) {
        switch opcode {
        case 0x0:
            guard fragmentedOpcode != nil else {
                closeSynchronously(
                    notifying: true,
                    error: UnixWebSocketError.invalidFrame
                )
                return
            }
            fragmentedMessage.append(payload)
            guard fragmentedMessage.count <= Self.maximumMessageBytes else {
                closeSynchronously(
                    notifying: true,
                    error: UnixWebSocketError.messageTooLarge
                )
                return
            }
            if isFinal {
                finishFragmentedMessage()
            }
        case 0x1:
            guard fragmentedOpcode == nil else {
                closeSynchronously(
                    notifying: true,
                    error: UnixWebSocketError.invalidFrame
                )
                return
            }
            if isFinal {
                onText(payload)
            } else {
                fragmentedOpcode = opcode
                fragmentedMessage = payload
            }
        case 0x8:
            closeSynchronously(
                notifying: true,
                error: UnixWebSocketError.closed
            )
        case 0x9:
            try? writeFrame(opcode: 0xA, payload: payload)
        case 0xA:
            break
        default:
            closeSynchronously(
                notifying: true,
                error: UnixWebSocketError.invalidFrame
            )
        }
    }

    private func finishFragmentedMessage() {
        let opcode = fragmentedOpcode
        let message = fragmentedMessage
        fragmentedOpcode = nil
        fragmentedMessage.removeAll(keepingCapacity: false)
        if opcode == 0x1 {
            onText(message)
        }
    }

    private func writeFrame(opcode: UInt8, payload: Data) throws {
        guard descriptor >= 0 else {
            throw UnixWebSocketError.closed
        }
        var frame = Data([0x80 | opcode])
        let count = payload.count
        if count < 126 {
            frame.append(UInt8(0x80 | count))
        } else if count <= Int(UInt16.max) {
            frame.append(0x80 | 126)
            frame.append(UInt8((count >> 8) & 0xFF))
            frame.append(UInt8(count & 0xFF))
        } else {
            frame.append(0x80 | 127)
            let length = UInt64(count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }

        var maskValue = UInt32.random(in: .min ... .max)
        let mask = withUnsafeBytes(of: &maskValue) { Array($0) }
        frame.append(contentsOf: mask)
        frame.append(
            contentsOf: payload.enumerated().map { index, byte in
                byte ^ mask[index % 4]
            }
        )
        try writeAll(frame, to: descriptor)
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            var written = 0
            while written < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                if count > 0 {
                    written += count
                    continue
                }
                if count < 0 && errno == EINTR {
                    continue
                }
                throw UnixWebSocketError.systemCall(
                    operation: "write",
                    code: errno
                )
            }
        }
    }

    private func closeSynchronously(
        notifying: Bool,
        error: Error?
    ) {
        let source = readSource
        readSource = nil
        source?.cancel()

        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
            descriptor = -1
        }
        receiveBuffer.removeAll(keepingCapacity: false)
        fragmentedMessage.removeAll(keepingCapacity: false)
        fragmentedOpcode = nil

        if notifying && !didNotifyClose {
            didNotifyClose = true
            onClose(error)
        }
    }
}

private enum UnixWebSocketError: LocalizedError {
    case closed
    case invalidFrame
    case invalidHandshake(String)
    case messageTooLarge
    case socketPathTooLong(String)
    case systemCall(operation: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .closed:
            return "The Codex control socket closed."
        case .invalidFrame:
            return "Codex sent an invalid control-socket frame."
        case .invalidHandshake(let message):
            return message
        case .messageTooLarge:
            return "Codex sent an unexpectedly large control-socket message."
        case .socketPathTooLong(let path):
            return "The Codex control-socket path is too long: \(path)"
        case .systemCall(let operation, let code):
            return "Codex control-socket \(operation) failed: "
                + String(cString: strerror(code))
        }
    }
}
