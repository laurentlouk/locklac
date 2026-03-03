import AppKit

public protocol OverlayWindowDelegate: AnyObject {
    func overlayDidSubmitPassword(_ password: String)
}

public final class OverlayWindowController {
    private var windows: [NSWindow] = []
    private var passwordField: NSSecureTextField?
    private var errorLabel: NSTextField?
    public weak var delegate: OverlayWindowDelegate?

    /// Called when the password field gains or loses focus (true = focused).
    public var onPasswordFieldFocusChanged: ((Bool) -> Void)?

    public init() {}

    public func show() {
        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        refocusPasswordField()
    }

    public func refocusPasswordField() {
        // Skip if password field already has focus (has an active field editor)
        if passwordField?.currentEditor() != nil { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let primaryWindow = windows.first {
            primaryWindow.makeKeyAndOrderFront(nil)
            passwordField?.becomeFirstResponder()
        }
    }

    public func hide() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        passwordField = nil
        errorLabel = nil
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
        let window = KeyableWindow(
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
        tintView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.3).cgColor
        tintView.autoresizingMask = [.width, .height]
        contentView.addSubview(tintView)

        if screen == NSScreen.main {
            addPasswordUI(to: contentView, frame: screen.frame)
            window.passwordField = passwordField
            window.onFirstResponderChanged = { [weak self] focused in
                self?.onPasswordFieldFocusChanged?(focused)
            }
        }

        window.contentView = contentView
        return window
    }

    private func addPasswordUI(to view: NSView, frame: NSRect) {
        let centerX = frame.midX
        let centerY = frame.midY

        // Pixel art food ball
        let pixelArtSize: CGFloat = 120
        let pixelArt = PixelArtView(frame: NSRect(
            x: centerX - pixelArtSize / 2,
            y: centerY + 30,
            width: pixelArtSize,
            height: pixelArtSize
        ))
        view.addSubview(pixelArt)

        let foodEmojis = ["🍙", "🍕", "🍣", "🍜", "🍩", "🍔", "🌮", "🍦", "🧁", "🍡",
                          "🥟", "🍰", "🍪", "🥐", "🍿", "🥯", "🍱", "🫕", "🥮", "🍘"]
        let randomEmoji = foodEmojis.randomElement()!
        let titleLabel = NSTextField(labelWithString: "LockLac \(randomEmoji)")
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .light)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: centerX - 120, y: centerY + 5, width: 240, height: 30)
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
        field.wantsLayer = true
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -6, 5, -4, 3, 0]
        animation.duration = 0.3
        animation.isAdditive = true
        field.layer?.add(animation, forKey: "shake")
    }
}

// MARK: - KeyableWindow

private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    weak var passwordField: NSView?
    var onFirstResponderChanged: ((Bool) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        // Click outside the password field → unfocus it
        if event.type == .leftMouseDown,
           let passwordField = passwordField,
           let superview = passwordField.superview {
            let localPoint = superview.convert(event.locationInWindow, from: nil)
            if !passwordField.frame.contains(localPoint) {
                _ = makeFirstResponder(nil)
            }
        }
        super.sendEvent(event)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        let isFocused = (passwordField as? NSTextField)?.currentEditor() != nil
        onFirstResponderChanged?(isFocused)
        return result
    }
}

// MARK: - Pixel Art Loc Lac

private final class PixelArtView: NSView {
    // 16x16 pixel art: loc lac beef on a plate
    // 0 = transparent, 1 = dark outline, 2 = beef brown, 3 = beef seared,
    // 4 = plate cream, 5 = lettuce green, 6 = lime green
    private static let grid: [[UInt8]] = [
        [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
        [0,0,0,1,1,4,4,4,4,4,4,1,1,0,0,0],
        [0,0,1,4,4,4,4,4,4,4,4,4,4,1,0,0],
        [0,1,4,4,5,5,5,5,5,5,5,5,4,4,1,0],
        [0,1,4,5,1,1,1,1,1,1,1,1,5,4,1,0],
        [1,4,5,1,2,2,1,3,3,1,2,2,1,5,4,1],
        [1,4,5,1,2,3,1,3,2,1,2,3,1,5,4,1],
        [1,4,4,1,1,1,1,1,1,1,1,1,1,4,4,1],
        [1,4,4,1,3,3,1,2,2,1,3,3,1,4,4,1],
        [1,4,5,1,3,2,1,2,3,1,3,2,1,5,4,1],
        [0,1,4,5,1,1,1,1,1,1,1,1,5,4,1,0],
        [0,1,4,4,5,5,5,5,5,5,5,5,4,4,1,0],
        [0,0,1,4,4,4,4,4,4,6,6,4,4,1,0,0],
        [0,0,0,1,4,4,4,4,6,6,6,4,1,0,0,0],
        [0,0,0,0,1,1,4,4,4,6,1,1,0,0,0,0],
        [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
    ]

    private static let palette: [UInt8: NSColor] = [
        0: .clear,
        1: NSColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1.0),  // dark outline
        2: NSColor(red: 0.63, green: 0.32, blue: 0.18, alpha: 1.0),  // beef brown
        3: NSColor(red: 0.42, green: 0.20, blue: 0.06, alpha: 1.0),  // beef seared
        4: NSColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1.0),  // plate cream
        5: NSColor(red: 0.36, green: 0.55, blue: 0.24, alpha: 1.0),  // lettuce green
        6: NSColor(red: 0.64, green: 0.79, blue: 0.23, alpha: 1.0),  // lime green
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rows = Self.grid.count
        let cols = Self.grid[0].count
        let pixelW = bounds.width / CGFloat(cols)
        let pixelH = bounds.height / CGFloat(rows)

        for row in 0..<rows {
            for col in 0..<cols {
                let value = Self.grid[rows - 1 - row][col] // flip Y for AppKit coords
                guard let color = Self.palette[value], value != 0 else { continue }
                color.setFill()
                let rect = NSRect(
                    x: CGFloat(col) * pixelW,
                    y: CGFloat(row) * pixelH,
                    width: pixelW + 0.5, // slight overlap to avoid gaps
                    height: pixelH + 0.5
                )
                rect.fill()
            }
        }
    }
}
