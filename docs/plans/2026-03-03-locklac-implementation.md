# lockLac Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS menu bar app that locks the screen with a fullscreen overlay, traps all input, and unlocks only with the correct password.

**Architecture:** Pure Swift, AppKit-based menu bar agent (LSUIElement). Library target `LockLacCore` holds all testable logic; thin `locklac` executable wires it up. CGEvent tap for global input capture, NSWindow overlay for visual lock, Unix domain socket for SSH kill switch.

**Tech Stack:** Swift 5.9+, AppKit, CoreGraphics (CGEvent), CommonCrypto (PBKDF2-SHA512 for password hashing — upgrade path to argon2id noted), Foundation (JSON config, Unix sockets)

---

### Task 1: Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/LockLacCore/LockLacCore.swift` (placeholder)
- Create: `Sources/locklac/main.swift` (placeholder)
- Create: `Tests/LockLacCoreTests/LockLacCoreTests.swift` (placeholder)

**Step 1: Initialize Swift Package**

```bash
cd /Users/U1096816/lockLac
swift package init --type executable --name locklac
```

This creates the default structure. We'll restructure it.

**Step 2: Rewrite Package.swift**

Replace the generated `Package.swift` with:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lockLac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "LockLacCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .executableTarget(
            name: "locklac",
            dependencies: ["LockLacCore"]
        ),
        .testTarget(
            name: "LockLacCoreTests",
            dependencies: ["LockLacCore"]
        ),
    ]
)
```

**Step 3: Create directory structure**

```bash
rm -rf Sources/locklac   # remove generated default
mkdir -p Sources/LockLacCore
mkdir -p Sources/locklac
mkdir -p Tests/LockLacCoreTests
```

**Step 4: Create placeholder files**

`Sources/LockLacCore/LockLacCore.swift`:
```swift
import Foundation

public enum LockLacCore {
    public static let version = "0.1.0"
}
```

`Sources/locklac/main.swift`:
```swift
import LockLacCore
print("lockLac v\(LockLacCore.version)")
```

`Tests/LockLacCoreTests/LockLacCoreTests.swift`:
```swift
import Testing
@testable import LockLacCore

@Test func versionExists() {
    #expect(!LockLacCore.version.isEmpty)
}
```

**Step 5: Verify build and tests**

```bash
swift build
swift test
swift run locklac
```

Expected: Build succeeds, test passes, prints "lockLac v0.1.0".

**Step 6: Commit**

```bash
git add Package.swift Sources/ Tests/
git commit -m "feat: scaffold Swift package with LockLacCore library and locklac executable"
```

---

### Task 2: PasswordStore (TDD)

**Files:**
- Create: `Sources/LockLacCore/PasswordStore.swift`
- Create: `Tests/LockLacCoreTests/PasswordStoreTests.swift`

**Step 1: Write failing tests**

`Tests/LockLacCoreTests/PasswordStoreTests.swift`:
```swift
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
```

**Step 2: Run tests to verify they fail**

```bash
swift test --filter LockLacCoreTests
```

Expected: FAIL — `PasswordStore` not found.

**Step 3: Implement PasswordStore**

`Sources/LockLacCore/PasswordStore.swift`:
```swift
import Foundation
import CommonCrypto

public final class PasswordStore {
    private let configDir: URL
    private var config: PasswordConfig?

    public var hasPassword: Bool { config != nil }

    public init(configDir: URL? = nil) {
        self.configDir = configDir ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".locklac")
    }

    public func load() throws {
        let configFile = configDir.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configFile.path) else { return }
        let data = try Data(contentsOf: configFile)
        config = try JSONDecoder().decode(PasswordConfig.self, from: data)
    }

    public func setPassword(_ password: String) throws {
        let salt = generateSalt()
        let hash = deriveKey(password: password, salt: salt)
        config = PasswordConfig(
            passwordHash: hash.base64EncodedString(),
            salt: salt.base64EncodedString(),
            iterations: Self.iterations,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try save()
    }

    public func verify(_ password: String) -> Bool {
        guard let config else { return false }
        guard let salt = Data(base64Encoded: config.salt),
              let storedHash = Data(base64Encoded: config.passwordHash) else { return false }
        let candidateHash = deriveKey(password: password, salt: salt, iterations: config.iterations)
        return constantTimeEqual(candidateHash, storedHash)
    }

    // MARK: - Private

    private static let iterations: UInt32 = 100_000
    private static let keyLength = 64
    private static let saltLength = 32

    private func generateSalt() -> Data {
        var salt = Data(count: Self.saltLength)
        salt.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, Self.saltLength, ptr.baseAddress!)
        }
        return salt
    }

    private func deriveKey(password: String, salt: Data, iterations: UInt32? = nil) -> Data {
        let passwordData = Array(password.utf8)
        var derivedKey = Data(count: Self.keyLength)
        derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordData, passwordData.count,
                    saltPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                    iterations ?? Self.iterations,
                    derivedKeyPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), Self.keyLength
                )
            }
        }
        return derivedKey
    }

    private func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a, b) {
            result |= x ^ y
        }
        return result == 0
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(config)
        let configFile = configDir.appendingPathComponent("config.json")
        try data.write(to: configFile, options: .atomic)
        // Set file permissions to owner-only (0600)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
    }
}

struct PasswordConfig: Codable {
    let passwordHash: String
    let salt: String
    let iterations: UInt32
    let createdAt: String
}
```

**Step 4: Run tests to verify they pass**

```bash
swift test --filter LockLacCoreTests
```

Expected: All 5 tests PASS.

**Step 5: Commit**

```bash
git add Sources/LockLacCore/PasswordStore.swift Tests/LockLacCoreTests/PasswordStoreTests.swift
git commit -m "feat: add PasswordStore with PBKDF2-SHA512 hashing and config persistence"
```

---

### Task 3: LockController State Machine (TDD)

**Files:**
- Create: `Sources/LockLacCore/LockController.swift`
- Create: `Tests/LockLacCoreTests/LockControllerTests.swift`

**Step 1: Write failing tests**

`Tests/LockLacCoreTests/LockControllerTests.swift`:
```swift
import Testing
import Foundation
@testable import LockLacCore

// Mock delegate to capture callbacks
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
    #expect(controller.state == .idle) // should not lock without password
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
```

**Step 2: Run tests to verify they fail**

```bash
swift test --filter LockController
```

Expected: FAIL — `LockController` not found.

**Step 3: Implement LockController**

`Sources/LockLacCore/LockController.swift`:
```swift
import Foundation

public enum LockState: Equatable {
    case idle
    case locked
}

public protocol LockControllerDelegate: AnyObject {
    func lockControllerDidLock()
    func lockControllerDidUnlock()
    func lockControllerPasswordIncorrect()
}

public final class LockController {
    public private(set) var state: LockState = .idle
    public weak var delegate: LockControllerDelegate?
    private let passwordStore: PasswordStore

    public init(passwordStore: PasswordStore) {
        self.passwordStore = passwordStore
    }

    public func lock() {
        guard state == .idle, passwordStore.hasPassword else { return }
        state = .locked
        delegate?.lockControllerDidLock()
    }

    public func attemptUnlock(password: String) -> Bool {
        guard state == .locked else { return false }
        if passwordStore.verify(password) {
            state = .idle
            delegate?.lockControllerDidUnlock()
            return true
        } else {
            delegate?.lockControllerPasswordIncorrect()
            return false
        }
    }

    public func forceUnlock() {
        guard state == .locked else { return }
        state = .idle
        delegate?.lockControllerDidUnlock()
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
swift test --filter LockController
```

Expected: All 7 tests PASS.

**Step 5: Commit**

```bash
git add Sources/LockLacCore/LockController.swift Tests/LockLacCoreTests/LockControllerTests.swift
git commit -m "feat: add LockController state machine with delegate callbacks"
```

---

### Task 4: SocketServer for SSH Kill Switch (TDD)

**Files:**
- Create: `Sources/LockLacCore/SocketServer.swift`
- Create: `Tests/LockLacCoreTests/SocketServerTests.swift`

**Step 1: Write failing tests**

`Tests/LockLacCoreTests/SocketServerTests.swift`:
```swift
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

    // Give server a moment to start listening
    Thread.sleep(forTimeInterval: 0.1)

    // Connect as client and send UNLOCK
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
```

**Step 2: Run tests to verify they fail**

```bash
swift test --filter SocketServer
```

Expected: FAIL — `SocketServer` not found.

**Step 3: Implement SocketServer**

`Sources/LockLacCore/SocketServer.swift`:
```swift
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
        // Remove stale socket if exists
        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw SocketError.createFailed
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let dest = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                strncpy(dest, ptr, MemoryLayout.size(ofValue: addr.sun_path) - 1)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        guard withUnsafePointer(to: &addr, { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, addrLen)
            }
        }) == 0 else {
            close(serverSocket)
            throw SocketError.bindFailed
        }

        // Set owner-only permissions
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
                        DispatchQueue.main.async { onUnlock() }
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

    /// Client-side: send unlock command to a running lockLac instance
    public static func sendUnlockCommand(to socketPath: String = "/tmp/locklac.sock") -> Bool {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPath in
                let dest = UnsafeMutableRawPointer(sunPath).assumingMemoryBound(to: CChar.self)
                strncpy(dest, ptr, MemoryLayout.size(ofValue: addr.sun_path) - 1)
            }
        }

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

    enum SocketError: Error {
        case createFailed
        case bindFailed
        case listenFailed
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
swift test --filter SocketServer
```

Expected: All 3 tests PASS.

**Step 5: Commit**

```bash
git add Sources/LockLacCore/SocketServer.swift Tests/LockLacCoreTests/SocketServerTests.swift
git commit -m "feat: add SocketServer for SSH kill switch via Unix domain socket"
```

---

### Task 5: EventTap — Global Input Capture

**Files:**
- Create: `Sources/LockLacCore/EventTap.swift`

This subsystem cannot be unit tested (requires Accessibility permissions and a running event loop). We verify manually.

**Step 1: Implement EventTap**

`Sources/LockLacCore/EventTap.swift`:
```swift
import CoreGraphics
import Foundation

public final class EventTap {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var enabled = false

    /// Callback invoked with keyboard events (keyDown) while locked.
    /// Return true to allow the event through, false to suppress.
    public var onKeyEvent: ((_ keyCode: UInt16, _ flags: CGEventFlags) -> Bool)?

    public init() {}

    public func start() -> Bool {
        // Check Accessibility permission
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        )
        guard trusted else { return false }

        let eventMask: CGEventMask = ~0 // all events

        // Store self pointer for the C callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        )

        guard let eventTap else { return false }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        enabled = true
        return true
    }

    public func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        self.eventTap = nil
        self.runLoopSource = nil
        enabled = false
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If tap is disabled by system, re-enable it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        // For keyDown events, ask the callback if we should allow it
        if type == .keyDown, let onKeyEvent {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            if onKeyEvent(keyCode, flags) {
                return Unmanaged.passRetained(event)
            }
        }

        // Suppress everything else (mouse moves, clicks, scrolls, other keys)
        return nil
    }
}
```

**Step 2: Verify it builds**

```bash
swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/LockLacCore/EventTap.swift
git commit -m "feat: add EventTap for global input capture via CGEvent"
```

---

### Task 6: Overlay Window

**Files:**
- Create: `Sources/LockLacCore/OverlayWindow.swift`

AppKit UI — manual verification only.

**Step 1: Implement OverlayWindow**

`Sources/LockLacCore/OverlayWindow.swift`:
```swift
import AppKit

public protocol OverlayWindowDelegate: AnyObject {
    func overlayDidSubmitPassword(_ password: String)
}

public final class OverlayWindowController {
    private var windows: [NSWindow] = []
    private var passwordField: NSSecureTextField?
    private var errorLabel: NSTextField?
    public weak var delegate: OverlayWindowDelegate?

    public init() {}

    public func show() {
        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        // Password field is on the primary screen's window
        if let primaryWindow = windows.first {
            primaryWindow.makeKey()
            passwordField?.becomeFirstResponder()
        }

        NSCursor.hide()
    }

    public func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        passwordField = nil
        errorLabel = nil
        NSCursor.unhide()
    }

    public func showError(_ message: String) {
        errorLabel?.stringValue = message
        errorLabel?.isHidden = false
        shakePasswordField()

        // Clear error after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.errorLabel?.isHidden = true
        }
    }

    public func clearPasswordField() {
        passwordField?.stringValue = ""
    }

    // MARK: - Private

    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let contentView = NSView(frame: screen.frame)

        // Dark blur background
        let blurView = NSVisualEffectView(frame: screen.frame)
        blurView.material = .dark
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        contentView.addSubview(blurView)

        // Additional dark tint
        let tintView = NSView(frame: screen.frame)
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
        tintView.autoresizingMask = [.width, .height]
        contentView.addSubview(tintView)

        // Only add password UI to the primary screen
        if screen == NSScreen.main {
            addPasswordUI(to: contentView, frame: screen.frame)
        }

        window.contentView = contentView
        return window
    }

    private func addPasswordUI(to view: NSView, frame: NSRect) {
        let centerX = frame.midX
        let centerY = frame.midY

        // Lock icon (SF Symbol or Unicode)
        let lockLabel = NSTextField(labelWithString: "\u{1F512}")
        lockLabel.font = NSFont.systemFont(ofSize: 48)
        lockLabel.alignment = .center
        lockLabel.frame = NSRect(x: centerX - 30, y: centerY + 40, width: 60, height: 60)
        lockLabel.textColor = .white
        view.addSubview(lockLabel)

        // "Locked" title
        let titleLabel = NSTextField(labelWithString: "lockLac")
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: centerX - 100, y: centerY + 5, width: 200, height: 30)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        view.addSubview(titleLabel)

        // Password field
        let field = NSSecureTextField(frame: NSRect(x: centerX - 140, y: centerY - 40, width: 280, height: 32))
        field.placeholderString = "Enter password to unlock"
        field.font = NSFont.systemFont(ofSize: 14)
        field.alignment = .center
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.target = self
        field.action = #selector(passwordSubmitted)
        view.addSubview(field)
        passwordField = field

        // Error label
        let error = NSTextField(labelWithString: "")
        error.font = NSFont.systemFont(ofSize: 13)
        error.alignment = .center
        error.frame = NSRect(x: centerX - 140, y: centerY - 75, width: 280, height: 20)
        error.textColor = NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
        error.isHidden = true
        view.addSubview(error)
        errorLabel = error
    }

    @objc private func passwordSubmitted() {
        guard let password = passwordField?.stringValue, !password.isEmpty else { return }
        delegate?.overlayDidSubmitPassword(password)
    }

    private func shakePasswordField() {
        guard let field = passwordField else { return }
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = [0, -10, 10, -10, 10, -5, 5, 0].map { field.frame.midX + $0 }
        animation.duration = 0.4
        field.layer?.add(animation, forKey: "shake")
    }
}
```

**Step 2: Verify it builds**

```bash
swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/LockLacCore/OverlayWindow.swift
git commit -m "feat: add OverlayWindowController with dark blur overlay and password field"
```

---

### Task 7: AppDelegate + Menu Bar Agent

**Files:**
- Create: `Sources/LockLacCore/AppDelegate.swift`

**Step 1: Implement AppDelegate**

`Sources/LockLacCore/AppDelegate.swift`:
```swift
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlayController = OverlayWindowController()
    private var lockController: LockController!
    private let passwordStore = PasswordStore()
    private let socketServer = SocketServer()
    private let eventTap = EventTap()

    public override init() {
        super.init()
        do {
            try passwordStore.load()
        } catch {
            print("Warning: could not load password config: \(error)")
        }
        lockController = LockController(passwordStore: passwordStore)
        lockController.delegate = self
        overlayController.delegate = self
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "lockLac")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Lock", action: #selector(lockAction), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Change Password", action: #selector(changePasswordAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func lockAction() {
        if !passwordStore.hasPassword {
            promptSetPassword { [weak self] in
                self?.performLock()
            }
            return
        }
        performLock()
    }

    private func performLock() {
        lockController.lock()
    }

    @objc private func changePasswordAction() {
        promptSetPassword(completion: nil)
    }

    @objc private func quitAction() {
        if lockController.state == .locked {
            return // cannot quit while locked
        }
        NSApplication.shared.terminate(nil)
    }

    private func promptSetPassword(completion: (() -> Void)?) {
        let alert = NSAlert()
        alert.messageText = "Set lockLac Password"
        alert.informativeText = "Enter a password to use for locking:"
        alert.addButton(withTitle: "Set Password")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Password"
        alert.accessoryView = field

        let response = alert.runModal()
        if response == .alertFirstButtonReturn, !field.stringValue.isEmpty {
            do {
                try passwordStore.setPassword(field.stringValue)
                completion?()
            } catch {
                let errAlert = NSAlert()
                errAlert.messageText = "Error"
                errAlert.informativeText = "Failed to save password: \(error.localizedDescription)"
                errAlert.runModal()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
        socketServer.stop()
    }
}

// MARK: - LockControllerDelegate

extension AppDelegate: LockControllerDelegate {
    public func lockControllerDidLock() {
        overlayController.show()
        let started = eventTap.start()
        if !started {
            // Accessibility permission denied — unlock and warn
            lockController.forceUnlock()
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "lockLac needs Accessibility permission to capture input.\n\nGo to System Settings → Privacy & Security → Accessibility and enable lockLac."
            alert.runModal()
            return
        }

        // Route keystrokes to the password field
        eventTap.onKeyEvent = { _, _ in
            // Allow all key events — they'll be captured by the overlay's text field
            // since it's the first responder. The event tap prevents them from reaching
            // other apps because the overlay window is key.
            return true
        }

        // Start socket server for SSH unlock
        do {
            try socketServer.start { [weak self] in
                self?.lockController.forceUnlock()
            }
        } catch {
            print("Warning: could not start socket server: \(error)")
        }

        // Warp mouse to center of primary screen
        if let screen = NSScreen.main {
            let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            CGWarpMouseCursorPosition(center)
        }
    }

    public func lockControllerDidUnlock() {
        eventTap.stop()
        overlayController.hide()
        socketServer.stop()
    }

    public func lockControllerPasswordIncorrect() {
        overlayController.showError("Incorrect password")
        overlayController.clearPasswordField()
    }
}

// MARK: - OverlayWindowDelegate

extension AppDelegate: OverlayWindowDelegate {
    public func overlayDidSubmitPassword(_ password: String) {
        _ = lockController.attemptUnlock(password: password)
    }
}
```

**Step 2: Verify it builds**

```bash
swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/LockLacCore/AppDelegate.swift
git commit -m "feat: add AppDelegate with menu bar agent, wiring all subsystems together"
```

---

### Task 8: Main Entry Point + CLI Arguments

**Files:**
- Modify: `Sources/locklac/main.swift`

**Step 1: Implement main.swift with CLI argument handling**

`Sources/locklac/main.swift`:
```swift
import AppKit
import LockLacCore

// CLI argument handling
let args = CommandLine.arguments

if args.contains("--unlock") {
    // SSH kill switch mode: send unlock command and exit
    let success = SocketServer.sendUnlockCommand()
    if success {
        print("lockLac unlocked successfully.")
    } else {
        print("Failed to unlock. Is lockLac running and locked?")
        exit(1)
    }
    exit(0)
}

if args.contains("set-password") {
    // Interactive password set mode
    let store = PasswordStore()
    print("Enter new password: ", terminator: "")
    guard let password = readLine(strippingNewline: true), !password.isEmpty else {
        print("Password cannot be empty.")
        exit(1)
    }
    print("Confirm password: ", terminator: "")
    guard let confirm = readLine(strippingNewline: true), confirm == password else {
        print("Passwords do not match.")
        exit(1)
    }
    do {
        try store.setPassword(password)
        print("Password set successfully.")
    } catch {
        print("Failed to set password: \(error)")
        exit(1)
    }
    exit(0)
}

if args.contains("--version") {
    print("lockLac v\(LockLacCore.version)")
    exit(0)
}

if args.contains("--help") {
    print("""
    lockLac — Lock your Mac while background tasks run

    Usage:
      locklac              Start the menu bar app
      locklac lock         Start the app and immediately lock
      locklac set-password Set or change the lock password
      locklac --unlock     Unlock a running instance (for SSH)
      locklac --version    Print version
      locklac --help       Print this help
    """)
    exit(0)
}

// Start the menu bar app
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // LSUIElement — no Dock icon
let delegate = AppDelegate()
app.delegate = delegate

// If `lock` argument is passed, lock immediately after launch
if args.contains("lock") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        delegate.lockAction()
    }
}

app.run()
```

Note: `lockAction` needs to be made public or exposed differently. Update `AppDelegate.swift` — change `@objc private func lockAction()` to `@objc public func lockAction()`.

**Step 2: Verify build and basic CLI**

```bash
swift build
swift run locklac --version
swift run locklac --help
```

Expected: Prints version and help text.

**Step 3: Commit**

```bash
git add Sources/locklac/main.swift Sources/LockLacCore/AppDelegate.swift
git commit -m "feat: add CLI entry point with lock, unlock, set-password, and menu bar app modes"
```

---

### Task 9: Info.plist for LSUIElement

**Files:**
- Create: `Sources/locklac/Info.plist`
- Modify: `Package.swift` (add plist reference)

**Step 1: Create Info.plist**

`Sources/locklac/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>lockLac</string>
    <key>CFBundleIdentifier</key>
    <string>com.locklac.app</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>lockLac needs to control input to lock your screen.</string>
</dict>
</plist>
```

**Step 2: Verify build**

```bash
swift build
```

Expected: Build succeeds.

**Step 3: Commit**

```bash
git add Sources/locklac/Info.plist Package.swift
git commit -m "feat: add Info.plist with LSUIElement for menu-bar-only mode"
```

---

### Task 10: Integration Testing + Polish

**Step 1: Run all unit tests**

```bash
swift test
```

Expected: All tests pass.

**Step 2: Manual integration test**

1. Set a password:
```bash
swift run locklac set-password
```

2. Start the app:
```bash
swift run locklac
```

3. Verify: menu bar icon appears (lock shield icon)
4. Click "Lock" in menu bar
5. Verify: dark overlay covers screen, password field visible
6. Type wrong password → verify shake + error message
7. Type correct password → verify overlay disappears

**Step 3: Test SSH kill switch**

1. Lock the app (step 2 above)
2. From another terminal (or SSH):
```bash
swift run locklac --unlock
```
3. Verify: overlay disappears, app returns to idle

**Step 4: Final commit**

Fix any issues found during integration testing, then:

```bash
git add -A
git commit -m "fix: integration testing fixes and polish"
```

---

## Notes

- **Password hashing:** Currently uses PBKDF2-SHA512 via CommonCrypto (zero dependencies). The design calls for argon2id — this can be upgraded by swapping the hashing implementation in `PasswordStore.swift` using a SPM package like `swift-sodium` or vendored argon2 C code. The `PasswordStore` interface remains the same.
- **Multi-monitor:** Overlay creates one window per screen. Password field is on the primary screen only.
- **Swift concurrency:** AppDelegate uses `@objc` selectors for AppKit compatibility. Future cleanup can adopt `@MainActor` annotations.
- **Event tap re-enable:** If macOS disables the tap (timeout/user input), the callback automatically re-enables it.
