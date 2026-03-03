import LocalAuthentication

public enum BiometricResult {
    case success
    case cancelled
    case lockedOut
    case notAvailable
    case failed
}

public final class BiometricAuth {
    public static var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Returns the LAContext so the caller can call `invalidate()` to dismiss the dialog.
    @discardableResult
    public static func authenticate(reason: String, completion: @escaping (BiometricResult) -> Void) -> LAContext? {
        let context = LAContext()
        context.localizedFallbackTitle = "" // hide "Enter Password" — we have our own

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            let result = Self.classify(error)
            completion(result)
            return nil
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
            DispatchQueue.main.async {
                if success {
                    completion(.success)
                } else {
                    completion(Self.classify(authError as NSError?))
                }
            }
        }
        return context
    }

    private static func classify(_ error: NSError?) -> BiometricResult {
        guard let error, error.domain == LAError.errorDomain else { return .failed }
        switch LAError.Code(rawValue: error.code) {
        case .userCancel, .appCancel, .systemCancel:
            return .cancelled
        case .biometryLockout:
            return .lockedOut
        case .biometryNotAvailable, .biometryNotEnrolled:
            return .notAvailable
        default:
            return .failed
        }
    }
}
