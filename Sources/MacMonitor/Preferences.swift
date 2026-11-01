import Foundation

/// What to show plus snoozes, acknowledgements, and the app ignore list. Persisted across relaunch.
struct Preferences: Codable {
    /// Battery is off by default: a worn battery is usually something you already know about.
    var hiddenVitals: Set<Vital.Kind> = [.battery]
    var disabledAlerts: Set<Alert.Kind> = [.batteryService, .lowBatteryDegraded]
    /// Acknowledged alerts are snoozed until `.distantFuture`.
    var snoozedUntil: [String: Date] = [:]
    var ignoredApps: Set<String> = []

    private static let key = "preferences"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              var preferences = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        preferences.snoozedUntil = preferences.snoozedUntil.filter { $0.value > Date() }
        return preferences
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
