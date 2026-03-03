import ServiceManagement

@available(macOS 13.0, *)
public enum LaunchAtLogin {
    private static let service = SMAppService.mainApp

    public static var isEnabled: Bool {
        service.status == .enabled
    }

    public static func toggle() throws {
        if isEnabled {
            try service.unregister()
        } else {
            try service.register()
        }
    }
}
