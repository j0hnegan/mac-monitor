import Foundation
import ServiceManagement

enum LoginItem {
    private static let setupKey = "didRegisterLoginItem"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }

    /// Opt in once; after that, respect whatever the user chose.
    static func registerOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: setupKey) else { return }
        UserDefaults.standard.set(true, forKey: setupKey)
        setEnabled(true)
    }
}
