import Foundation

/// What to show plus snoozes, acknowledgements, and the app ignore list. Persisted across relaunch.
struct Preferences: Codable {
    /// Battery is off by default: a worn battery is usually something you already know about.
    var hiddenVitals: Set<Vital.Kind> = [.battery]
    var disabledAlerts: Set<Alert.Kind> = [.batteryService, .lowBatteryDegraded]
    /// Acknowledged alerts are snoozed until `.distantFuture`.
    var snoozedUntil: [String: Date] = [:]
    var ignoredApps: Set<String> = []
    var popUpAlerts = true
    /// Only apps you aren't using, after a countdown you can stop.
    var autoFixStuckApps = true

    init() {}

    /// Settings added later fall back to their defaults instead of throwing away everything saved.
    init(from decoder: Decoder) throws {
        let saved = try decoder.container(keyedBy: CodingKeys.self)
        hiddenVitals = try saved.decodeIfPresent(Set<Vital.Kind>.self, forKey: .hiddenVitals) ?? hiddenVitals
        disabledAlerts = try saved.decodeIfPresent(Set<Alert.Kind>.self, forKey: .disabledAlerts) ?? disabledAlerts
        snoozedUntil = try saved.decodeIfPresent([String: Date].self, forKey: .snoozedUntil) ?? snoozedUntil
        ignoredApps = try saved.decodeIfPresent(Set<String>.self, forKey: .ignoredApps) ?? ignoredApps
        popUpAlerts = try saved.decodeIfPresent(Bool.self, forKey: .popUpAlerts) ?? popUpAlerts
        autoFixStuckApps = try saved.decodeIfPresent(Bool.self, forKey: .autoFixStuckApps) ?? autoFixStuckApps
    }

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
