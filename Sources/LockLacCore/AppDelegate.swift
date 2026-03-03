import AppKit
import LocalAuthentication

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let overlayController = OverlayWindowController()
    private var lockController: LockController!
    private let passwordStore = PasswordStore()
    private let socketServer = SocketServer()
    private let eventTap = EventTap()
    private var biometricContext: LAContext?
    public var debugMode = false

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
        if !passwordStore.hasPassword {
            requirePassword()
        }
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
            promptSetPassword { [weak self] in self?.performLock() }
            return
        }
        performLock()
    }

    private func performLock() {
        lockController.lock()
    }

    @objc private func changePasswordAction() {
        promptSetPassword()
    }

    @objc private func quitAction() {
        if lockController.state == .locked {
            return
        }
        NSApplication.shared.terminate(nil)
    }

    /// Loops until the user sets a password. Used on first launch.
    private func requirePassword() {
        while !passwordStore.hasPassword {
            let didSet = promptSetPassword()
            if !didSet {
                let alert = NSAlert()
                alert.messageText = "Password Required"
                alert.informativeText = "lockLac requires a password to function. Please set one."
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    /// Returns true if password was successfully set.
    @discardableResult
    private func promptSetPassword(completion: (() -> Void)? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Set lockLac Password"
        alert.informativeText = "Enter a password to use for locking:"
        alert.addButton(withTitle: "Set Password")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        field.placeholderString = "Password"
        container.addSubview(field)

        let confirmField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        confirmField.placeholderString = "Confirm password"
        container.addSubview(confirmField)

        alert.accessoryView = container

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return false }

        let password = field.stringValue
        let confirm = confirmField.stringValue

        if password.isEmpty {
            showErrorAlert("Password cannot be empty.")
            return false
        }
        if password != confirm {
            showErrorAlert("Passwords do not match.")
            return false
        }

        do {
            try passwordStore.setPassword(password)
            completion?()
            return true
        } catch {
            showErrorAlert("Failed to save password: \(error.localizedDescription)")
            return false
        }
    }

    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.runModal()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        eventTap.stop()
        socketServer.stop()
    }
}

// MARK: - LockControllerDelegate

extension AppDelegate: LockControllerDelegate {
    public func lockControllerDidLock() {
        overlayController.onPasswordFieldFocusChanged = { [weak self] focused in
            self?.eventTap.keyboardPassthrough = focused
        }
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

        eventTap.onKeyEvent = { [weak self] keyCode, _ in
            // ESC (keyCode 53) unlocks in debug mode
            if self?.debugMode == true, keyCode == 53 {
                self?.lockController.forceUnlock()
                return false
            }
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

        attemptBiometricUnlock()
    }

    private func attemptBiometricUnlock() {
        guard lockController.state == .locked else { return }
        biometricContext = BiometricAuth.authenticate(reason: "Unlock lockLac") { [weak self] success in
            guard let self, self.lockController.state == .locked else { return }
            if success {
                self.lockController.forceUnlock()
            } else {
                // Re-prompt Touch ID after a short delay so it's always available
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.attemptBiometricUnlock()
                }
            }
        }
    }

    private func cancelBiometricAuth() {
        biometricContext?.invalidate()
        biometricContext = nil
    }

    public func lockControllerDidUnlock() {
        cancelBiometricAuth()
        eventTap.stop()
        overlayController.hide()
        socketServer.stop()
    }

    public func lockControllerPasswordIncorrect() {
        overlayController.showError("Incorrect password")
        overlayController.clearPasswordField()
        overlayController.refocusPasswordField()
    }
}

// MARK: - OverlayWindowDelegate

extension AppDelegate: OverlayWindowDelegate {
    public func overlayDidSubmitPassword(_ password: String) {
        _ = lockController.attemptUnlock(password: password)
    }
}
