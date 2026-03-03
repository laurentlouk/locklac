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

        let blurView = NSVisualEffectView(frame: screen.frame)
        blurView.material = .underPageBackground
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.appearance = NSAppearance(named: .darkAqua)
        blurView.autoresizingMask = [.width, .height]
        contentView.addSubview(blurView)

        let tintView = NSView(frame: screen.frame)
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.5).cgColor
        tintView.autoresizingMask = [.width, .height]
        contentView.addSubview(tintView)

        if screen == NSScreen.main {
            addPasswordUI(to: contentView, frame: screen.frame)
        }

        window.contentView = contentView
        return window
    }

    private func addPasswordUI(to view: NSView, frame: NSRect) {
        let centerX = frame.midX
        let centerY = frame.midY

        let lockLabel = NSTextField(labelWithString: "\u{1F512}")
        lockLabel.font = NSFont.systemFont(ofSize: 48)
        lockLabel.alignment = .center
        lockLabel.frame = NSRect(x: centerX - 30, y: centerY + 40, width: 60, height: 60)
        lockLabel.textColor = .white
        view.addSubview(lockLabel)

        let titleLabel = NSTextField(labelWithString: "lockLac")
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: centerX - 100, y: centerY + 5, width: 200, height: 30)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        view.addSubview(titleLabel)

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

        let error = NSTextField(labelWithString: "")
        error.font = NSFont.systemFont(ofSize: 13)
        error.alignment = .center
        error.frame = NSRect(x: centerX - 140, y: centerY - 75, width: 280, height: 20)
        error.textColor = NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
        error.isHidden = true
        view.addSubview(error)
        errorLabel = error

        if BiometricAuth.isAvailable {
            let touchIdHint = NSTextField(labelWithString: "or use Touch ID")
            touchIdHint.font = NSFont.systemFont(ofSize: 12)
            touchIdHint.alignment = .center
            touchIdHint.frame = NSRect(x: centerX - 100, y: centerY - 100, width: 200, height: 18)
            touchIdHint.textColor = NSColor.white.withAlphaComponent(0.5)
            view.addSubview(touchIdHint)
        }
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
