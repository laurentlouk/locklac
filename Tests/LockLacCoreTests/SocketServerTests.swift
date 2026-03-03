import Testing
import Foundation
@testable import LockLacCore

@Test func serverStartsAndStops() throws {
    let path = "/tmp/locklac-test-\(UUID().uuidString).sock"
    let server = SocketServer(socketPath: path)
    try server.start { }
    #expect(FileManager.default.fileExists(atPath: path))
    server.stop()
    #expect(!FileManager.default.fileExists(atPath: path))
}

@Test func clientCanSendUnlockCommand() throws {
    let path = "/tmp/locklac-test-\(UUID().uuidString).sock"
    let server = SocketServer(socketPath: path)
    var unlockCalled = false
    try server.start { unlockCalled = true }

    Thread.sleep(forTimeInterval: 0.1)

    let success = SocketServer.sendUnlockCommand(to: path)
    Thread.sleep(forTimeInterval: 0.1)

    #expect(success)
    #expect(unlockCalled)
    server.stop()
}

@Test func socketHasOwnerOnlyPermissions() throws {
    let path = "/tmp/locklac-test-\(UUID().uuidString).sock"
    let server = SocketServer(socketPath: path)
    try server.start { }

    let attrs = try FileManager.default.attributesOfItem(atPath: path)
    let perms = attrs[.posixPermissions] as? Int
    #expect(perms == 0o600)
    server.stop()
}
