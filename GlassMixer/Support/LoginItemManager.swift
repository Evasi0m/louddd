import Foundation
import ServiceManagement

/// Wraps the modern `SMAppService` "open at login" registration for the main app (macOS 13+).
/// `SMAppService` is itself the source of truth for the enabled state, so there's nothing to persist.
enum LoginItemManager {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister the app as a login item. Throws if the system rejects the change.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status == .enabled else { return }
            try service.unregister()
        }
    }
}
