import LocalAuthentication

public final class BiometricAuth {
    public static var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Returns the LAContext so the caller can call `invalidate()` to dismiss the dialog.
    @discardableResult
    public static func authenticate(reason: String, completion: @escaping (Bool) -> Void) -> LAContext? {
        let context = LAContext()
        context.localizedFallbackTitle = "" // hide "Enter Password" — we have our own

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return nil
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
        return context
    }
}
