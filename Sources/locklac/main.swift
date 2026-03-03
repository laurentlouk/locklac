import AppKit
import LockLacCore

let args = CommandLine.arguments

if args.contains("--unlock") {
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
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate

if args.contains("lock") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        delegate.lockAction()
    }
}

app.run()
