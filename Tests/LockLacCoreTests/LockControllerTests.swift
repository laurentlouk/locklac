import Testing
import Foundation
@testable import LockLacCore

final class MockLockDelegate: LockControllerDelegate {
    var didLockCalled = false
    var didUnlockCalled = false
    var incorrectPasswordCalled = false

    func lockControllerDidLock() { didLockCalled = true }
    func lockControllerDidUnlock() { didUnlockCalled = true }
    func lockControllerPasswordIncorrect() { incorrectPasswordCalled = true }
}

@Test func initialStateIsIdle() {
    let store = PasswordStore(configDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let controller = LockController(passwordStore: store)
    #expect(controller.state == .idle)
}

@Test func lockTransitionsToLocked() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PasswordStore(configDir: dir)
    try store.setPassword("test")
    let delegate = MockLockDelegate()
    let controller = LockController(passwordStore: store)
    controller.delegate = delegate
    controller.lock()
    #expect(controller.state == .locked)
    #expect(delegate.didLockCalled)
}

@Test func correctPasswordUnlocks() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PasswordStore(configDir: dir)
    try store.setPassword("secret")
    let delegate = MockLockDelegate()
    let controller = LockController(passwordStore: store)
    controller.delegate = delegate
    controller.lock()
    let result = controller.attemptUnlock(password: "secret")
    #expect(result)
    #expect(controller.state == .idle)
    #expect(delegate.didUnlockCalled)
}

@Test func wrongPasswordStaysLocked() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PasswordStore(configDir: dir)
    try store.setPassword("secret")
    let delegate = MockLockDelegate()
    let controller = LockController(passwordStore: store)
    controller.delegate = delegate
    controller.lock()
    let result = controller.attemptUnlock(password: "wrong")
    #expect(!result)
    #expect(controller.state == .locked)
    #expect(delegate.incorrectPasswordCalled)
}

@Test func forceUnlockFromLocked() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PasswordStore(configDir: dir)
    try store.setPassword("test")
    let delegate = MockLockDelegate()
    let controller = LockController(passwordStore: store)
    controller.delegate = delegate
    controller.lock()
    controller.forceUnlock()
    #expect(controller.state == .idle)
    #expect(delegate.didUnlockCalled)
}

@Test func lockWithoutPasswordFails() {
    let store = PasswordStore(configDir: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    let controller = LockController(passwordStore: store)
    controller.lock()
    #expect(controller.state == .idle)
}

@Test func cannotLockWhileAlreadyLocked() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = PasswordStore(configDir: dir)
    try store.setPassword("test")
    let delegate = MockLockDelegate()
    let controller = LockController(passwordStore: store)
    controller.delegate = delegate
    controller.lock()
    delegate.didLockCalled = false
    controller.lock() // second lock should be ignored
    #expect(!delegate.didLockCalled)
    #expect(controller.state == .locked)
}
