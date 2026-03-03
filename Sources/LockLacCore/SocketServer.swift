import Foundation

public final class SocketServer {
    private let socketPath: String
    private var serverSocket: Int32 = -1
    private var listening = false
    private var listenerThread: Thread?

    public init(socketPath: String = "/tmp/locklac.sock") {
        self.socketPath = socketPath
    }

    public func start(onUnlock: @escaping () -> Void) throws {
        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw SocketError.createFailed
        }

        var addr = Self.makeUnixAddr(path: socketPath)

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        guard withUnsafePointer(to: &addr, { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, addrLen)
            }
        }) == 0 else {
            close(serverSocket)
            throw SocketError.bindFailed
        }

        chmod(socketPath, 0o600)

        guard listen(serverSocket, 1) == 0 else {
            close(serverSocket)
            unlink(socketPath)
            throw SocketError.listenFailed
        }

        listening = true

        let thread = Thread {
            while self.listening {
                let client = accept(self.serverSocket, nil, nil)
                guard client >= 0, self.listening else { continue }

                var buffer = [UInt8](repeating: 0, count: 64)
                let bytesRead = read(client, &buffer, buffer.count)
                if bytesRead > 0 {
                    let command = String(bytes: buffer[0..<bytesRead], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if command == "UNLOCK" {
                        write(client, "OK\n", 3)
                        onUnlock()
                    }
                }
                close(client)
            }
        }
        thread.name = "locklac-socket"
        thread.start()
        listenerThread = thread
    }

    public func stop() {
        listening = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(socketPath)
    }

    public static func sendUnlockCommand(to socketPath: String = "/tmp/locklac.sock") -> Bool {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = makeUnixAddr(path: socketPath)

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr, { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, addrLen)
            }
        })
        guard connected == 0 else { return false }

        let command = "UNLOCK\n"
        write(sock, command, command.utf8.count)

        var buffer = [UInt8](repeating: 0, count: 16)
        let n = read(sock, &buffer, buffer.count)
        if n > 0, let response = String(bytes: buffer[0..<n], encoding: .utf8) {
            return response.trimmingCharacters(in: .whitespacesAndNewlines) == "OK"
        }
        return false
    }

    // MARK: - Private

    private static func makeUnixAddr(path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<sockaddr_un>.size) { base in
                let sunPathOffset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)!
                let dest = base.advanced(by: sunPathOffset)
                pathBytes.withUnsafeBufferPointer { src in
                    let count = min(src.count, 104) // sun_path is typically 104 bytes on macOS
                    src.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: count) { srcBytes in
                        dest.initialize(from: srcBytes, count: count)
                    }
                }
            }
        }
        return addr
    }

    enum SocketError: Error {
        case createFailed
        case bindFailed
        case listenFailed
    }
}
