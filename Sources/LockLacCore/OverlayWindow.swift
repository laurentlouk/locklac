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
        tintView.layer?.backgroundColor = NSColor(white: 0, alpha: 0.3).cgColor
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

        // Pixel art food ball
        let pixelArtSize: CGFloat = 120
        let pixelArt = PixelArtView(frame: NSRect(
            x: centerX - pixelArtSize / 2,
            y: centerY + 30,
            width: pixelArtSize,
            height: pixelArtSize
        ))
        view.addSubview(pixelArt)

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

// MARK: - Pixel Art Food Ball

private final class PixelArtView: NSView {
    // 16x16 pixel art: onigiri rice ball
    // 0 = transparent, 1 = dark outline, 2 = white rice, 3 = nori (seaweed), 4 = highlight
    private static let grid: [[UInt8]] = [
        [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
        [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
        [0,0,0,1,2,2,4,4,2,2,2,2,1,0,0,0],
        [0,0,1,2,2,4,4,2,2,2,2,2,2,1,0,0],
        [0,1,2,2,2,4,2,2,2,2,2,2,2,2,1,0],
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,1,0],
        [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
        [1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1],
        [1,2,2,2,2,1,1,1,1,1,1,2,2,2,2,1],
        [1,2,2,2,1,3,3,3,3,3,3,1,2,2,2,1],
        [0,1,2,2,1,3,3,3,3,3,3,1,2,2,1,0],
        [0,1,2,2,1,3,3,3,3,3,3,1,2,2,1,0],
        [0,0,1,2,1,3,3,3,3,3,3,1,2,1,0,0],
        [0,0,0,1,1,3,3,3,3,3,3,1,1,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
    ]

    private static let palette: [UInt8: NSColor] = [
        0: .clear,
        1: NSColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1.0),  // dark outline
        2: NSColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1.0),  // white rice
        3: NSColor(red: 0.10, green: 0.20, blue: 0.12, alpha: 1.0),  // nori seaweed
        4: NSColor(red: 1.00, green: 1.00, blue: 0.98, alpha: 1.0),  // highlight
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
