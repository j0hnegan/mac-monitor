import Foundation
import IOKit
import IOKit.ps

struct BatteryReading {
    let charge: Int
    let isCharging: Bool
    let onBattery: Bool
    let minutesRemaining: Int?
    let cycles: Int?
    /// "Maximum Capacity" as shown in System Settings > Battery.
    let healthPercent: Int?
    let serviceRecommended: Bool
}

final class BatteryCollector {
    private struct Condition {
        let healthPercent: Int?
        let serviceRecommended: Bool
    }

    private var condition: Condition?
    private var conditionReadAt = Date.distantPast

    /// Returns nil on Macs without an internal battery.
    func read() -> BatteryReading? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as NSArray as [CFTypeRef]
        guard let battery = sources
            .compactMap({ IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as NSDictionary? as? [String: Any] })
            .first(where: { $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType })
        else { return nil }

        // Health only changes over weeks; don't spawn pmset on every sample.
        if condition == nil || Date().timeIntervalSince(conditionReadAt) > 3600 {
            condition = Self.readCondition()
            conditionReadAt = Date()
        }

        let minutes = battery[kIOPSTimeToEmptyKey] as? Int ?? -1
        return BatteryReading(
            charge: battery[kIOPSCurrentCapacityKey] as? Int ?? 0,
            isCharging: battery[kIOPSIsChargingKey] as? Bool ?? false,
            onBattery: battery[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
            minutesRemaining: minutes > 0 ? minutes : nil,
            cycles: Self.registryValue("CycleCount"),
            healthPercent: condition?.healthPercent,
            serviceRecommended: condition?.serviceRecommended ?? false
        )
    }

    private static func registryValue(_ key: String) -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int
    }

    /// The public IOPS description omits health and service state on macOS 27, but powerd
    /// exposes both (matching System Settings) through `pmset -g ps -xml`.
    private static func readCondition() -> Condition? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "ps", "-xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let health = (plist["BatteryPacks"] as? [[String: Any]])?.first?["BatteryHealth"] as? [String: Any]
        return Condition(
            healthPercent: health?["Maximum Capacity Percent"] as? Int,
            serviceRecommended: (plist["Battery Service State"] as? Int ?? 0) != 0
        )
    }
}
