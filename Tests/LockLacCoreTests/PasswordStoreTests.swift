import Testing
import Foundation
@testable import LockLacCore

@Test func hashAndVerifyPassword() throws {
    let store = PasswordStore(configDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    try store.setPassword("correcthorse")
    #expect(store.verify("correcthorse"))
    #expect(!store.verify("wrongpassword"))
}

@Test func persistsPasswordToDisk() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store1 = PasswordStore(configDir: dir)
    try store1.setPassword("persist-test")

    // Load from disk in a new instance
    let store2 = PasswordStore(configDir: dir)
    try store2.load()
    #expect(store2.verify("persist-test"))
    #expect(!store2.verify("wrong"))
}

@Test func hasPasswordReturnsFalseWhenNoConfig() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PasswordStore(configDir: dir)
    #expect(!store.hasPassword)
}

@Test func hasPasswordReturnsTrueAfterSet() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PasswordStore(configDir: dir)
    try store.setPassword("test123")
    #expect(store.hasPassword)
}

@Test func differentSaltsProduceDifferentHashes() throws {
    let dir1 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let dir2 = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store1 = PasswordStore(configDir: dir1)
    let store2 = PasswordStore(configDir: dir2)
    try store1.setPassword("same-password")
    try store2.setPassword("same-password")

    let data1 = try Data(contentsOf: dir1.appendingPathComponent("config.json"))
    let data2 = try Data(contentsOf: dir2.appendingPathComponent("config.json"))
    // Files should differ because salts are random
    #expect(data1 != data2)
}
