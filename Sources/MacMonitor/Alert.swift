import Foundation

struct Alert: Identifiable {
    enum Kind: String, CaseIterable, Codable {
        case memoryHog = "memory_hog"
        case runawayProcess = "runaway_process"
        case memoryPressure = "memory_pressure"
        case uptime
        case lowBatteryDegraded = "low_battery_degraded"
        case batteryService = "battery_service"
        case lowDisk = "low_disk"
        case thermal

        /// How the alert type reads in Settings.
        var label: String {
            switch self {
            case .memoryHog: "An app is hogging memory while your Mac is short on it"
            case .runawayProcess: "An app is stuck using lots of CPU"
            case .memoryPressure: "Your Mac is out of memory"
            case .uptime: "Your Mac hasn't restarted in a while"
            case .lowBatteryDegraded: "Battery is low and worn"
            case .batteryService: "Battery needs service"
            case .lowDisk: "Disk is almost full"
            case .thermal: "Your Mac is running hot"
            }
        }
    }

    let kind: Kind
    /// What the alert is about. Part of the id, so snoozing one app's alert doesn't snooze another's.
    let subject: String
    let severity: Health
    let title: String
    let detail: String
    var fixes: [Fix] = []
    var notify = false
    /// Apps can be put on the ignore list from their alert's overflow menu.
    var app: String? = nil

    var id: String { "\(kind.rawValue):\(subject)" }
}

struct Fix: Identifiable {
    let id: String
    let title: String
    let action: FixAction
    /// When set, the user must confirm this message before the fix runs.
    var confirmation: String? = nil
}

/// Every fix in the app goes through these cases: alert buttons, notifications, and MCP.
enum FixAction {
    case quitApp(AppGroup)
    case restartApp(AppGroup)
    case forceQuit(pid: pid_t)
    case restartMac
    case openURL(URL)
    case showDetails(Vital.Kind)
    case acknowledge
    case remindTonight
}
