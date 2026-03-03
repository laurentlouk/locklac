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

    @objc public func lockAction() {
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
            return
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
            lockController.forceUnlock()
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "lockLac needs Accessibility permission to capture input.\n\nGo to System Settings \u{2192} Privacy & Security \u{2192} Accessibility and enable lockLac."
            alert.runModal()
            return
        }

        eventTap.onKeyEvent = { _, _ in
            return true
        }

        do {
            try socketServer.start { [weak self] in
                self?.lockController.forceUnlock()
            }
        } catch {
            print("Warning: could not start socket server: \(error)")
        }

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
