import Darwin
import Foundation

/// One line of JSON from a hook, already parsed. Unknown fields are ignored; nothing here can crash the app.
struct HookMessage: Sendable {
    let event: String
    let fields: [String: Sendable]

    func string(_ key: String) -> String? { fields[key] as? String }
    func bool(_ key: String) -> Bool? { fields[key] as? Bool }
    func int(_ key: String) -> Int? { (fields[key] as? Int) ?? (fields[key] as? Double).map(Int.init) }

    init?(line: Data) {
        guard let any = try? JSONSerialization.jsonObject(with: line), let object = any as? [String: Any],
              let event = object["event"] as? String else { return nil }
        self.event = event
        var out: [String: Sendable] = [:]
        for (key, value) in object {
            switch value {
            case let v as String: out[key] = v
            case let v as Bool: out[key] = v
            case let v as Int: out[key] = v
            case let v as Double: out[key] = v
            case let v as [String: Any]:
                if let data = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]),
                   let text = String(data: data, encoding: .utf8) { out[key] = text }
            default: break
            }
        }
        fields = out
    }
}

private struct Transfer<T>: @unchecked Sendable { let value: T }

/// Unix socket in ~/Library/Application Support/Cove (0700). Only this user's processes can connect.
/// Status events are one line and the client is gone. A PermissionRequest keeps its connection open until
/// `reply(to:decision:)` or `close(request:)`; closing without a decision makes the hook exit 0 with no output.
@MainActor
final class ClaudeSocket {
    static let directory = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Cove", isDirectory: true)
    static let path = directory.appendingPathComponent("cove.sock").path
    static let maxLine = 4_000_000

    private final class Connection {
        let fd: Int32
        var buffer = Data()
        var source: DispatchSourceRead?
        var requestID: String?
        init(fd: Int32) { self.fd = fd }
    }

    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]
    private var pending: [String: Int32] = [:]
    private let onMessage: @MainActor (HookMessage) -> Void
    /// Called when a PermissionRequest connection goes away without an answer (hook timed out or Claude moved on).
    private let onRequestClosed: @MainActor (String) -> Void

    init(onMessage: @escaping @MainActor (HookMessage) -> Void, onRequestClosed: @escaping @MainActor (String) -> Void) {
        self.onMessage = onMessage
        self.onRequestClosed = onRequestClosed
    }

    func start() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.directory.path)
        unlink(Self.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(Self.path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (i, byte) in bytes.enumerated() { buffer[i] = byte }
            buffer[bytes.count] = 0
        }
        let oldMask = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(oldMask)
        guard bound == 0, listen(fd, 16) == 0 else { Darwin.close(fd); throw POSIXError(.EADDRINUSE) }
        listenFD = fd
        let transfer = Transfer(value: self)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { transfer.value.accept() } }
        source.resume()
        listenSource = source
        Log.app.notice("Socket listening at \(Self.path, privacy: .public)")
    }

    func stop() {
        for connection in connections.values { closeConnection(connection) }
        listenSource?.cancel()
        if listenFD >= 0 { Darwin.close(listenFD) }
        unlink(Self.path)
    }

    private func accept() {
        let fd = Darwin.accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
            Log.app.error("Rejected socket client with uid \(uid)")
            Darwin.close(fd)
            return
        }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let connection = Connection(fd: fd)
        connections[fd] = connection
        let transfer = Transfer(value: self)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { transfer.value.readable(fd) } }
        source.resume()
        connection.source = source
    }

    private func readable(_ fd: Int32) {
        guard let connection = connections[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 65536)
        let n = read(fd, &chunk, chunk.count)
        if n <= 0 { closeConnection(connection); return }
        connection.buffer.append(chunk, count: n)
        if connection.buffer.count > Self.maxLine { closeConnection(connection); return }
        while let newline = connection.buffer.firstIndex(of: 0x0A) {
            let line = connection.buffer.subdata(in: connection.buffer.startIndex..<newline)
            connection.buffer.removeSubrange(connection.buffer.startIndex...newline)
            guard let message = HookMessage(line: line) else { continue }
            if let id = message.string("request_id"), message.event == "PermissionRequest" || message.event == "Stop" {
                connection.requestID = id
                pending[id] = fd
            }
            onMessage(message)
        }
    }

    /// Answers a waiting PermissionRequest hook and closes its connection. A deny may carry a message for Claude.
    func reply(to requestID: String, decision: String, message: String? = nil) {
        var object: [String: Any] = ["request_id": requestID, "decision": decision]
        if let message, !message.isEmpty { object["message"] = message }
        send(object, to: requestID)
    }

    /// Sends James's typed reply down a waiting Stop hook.
    func reply(to requestID: String, text: String) {
        send(["request_id": requestID, "reply": text], to: requestID)
    }

    /// Answers a waiting AskUserQuestion hook: question text → chosen label(s).
    func reply(to requestID: String, answers: [String: String]) {
        send(["request_id": requestID, "answers": answers], to: requestID)
    }

    func isPending(_ requestID: String) -> Bool { pending[requestID] != nil }

    private func send(_ object: [String: Any], to requestID: String) {
        guard let fd = pending[requestID], let connection = connections[fd],
              var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        connection.requestID = nil
        pending[requestID] = nil
        closeConnection(connection)
    }

    /// Closes a request's connection without a decision: the hook exits 0 and Claude asks as usual.
    func close(request requestID: String) {
        guard let fd = pending[requestID], let connection = connections[fd] else { return }
        connection.requestID = nil
        pending[requestID] = nil
        closeConnection(connection)
    }

    private func closeConnection(_ connection: Connection) {
        connection.source?.cancel()
        Darwin.close(connection.fd)
        connections[connection.fd] = nil
        if let id = connection.requestID {
            pending[id] = nil
            onRequestClosed(id)
        }
    }
}
