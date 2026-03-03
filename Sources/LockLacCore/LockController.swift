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
