import Foundation

/// Color and alert thresholds from PRD §6–7. Will become editable in Settings.
struct Thresholds {
    /// Swap growing this much within `swapWindow` means memory is short now, not just earlier.
    var swapGrowthBytes: UInt64 = 100 * 1_048_576
    var swapWindow: TimeInterval = 5 * 60
    var swapRedGB = 6.0
    /// Swap worth mentioning when memory is fine, and worth worrying about when memory is nearly full.
    var notableSwapGB = 2.0
    var nearlyFull = 0.9
    var cpuAmber = 0.60
    var cpuRed = 0.85
    var cpuWindow: TimeInterval = 5 * 60
    var batteryHealthAmber = 85
    var batteryChargeAmber = 20
    var batteryChargeRed = 10
    var diskFreeAmber = 0.15
    var diskFreeRed = 0.05
    var uptimeAmberDays = 7.0
    var uptimeRedDays = 21.0

    var memoryHogGB = 6.0
    var runawayCPU = 0.50
    var runawayWindow: TimeInterval = 10 * 60
    var memoryPressureWindow: TimeInterval = 2 * 60
    var uptimeAlertDays = 14.0
    var lowBatteryCharge = 15
    var batteryServiceHealth = 80
}

enum VitalRules {
    static func memory(_ m: MemoryReading, groups: [AppGroup], _ t: Thresholds) -> Vital {
        let swapGB = Format.gigabytes(m.swapUsed)
        let swapping = m.swapGrowth >= t.swapGrowthBytes
        let full = Double(m.used) / Double(m.total) >= t.nearlyFull && swapGB >= t.notableSwapGB
        // Judged by what's happening now, not by swap size alone: swap lingers for hours after
        // a squeeze (or after waking from hibernation) while the Mac has plenty of room.
        let health: Health =
            m.pressure == .critical || (m.pressure == .warn && swapGB > t.swapRedGB) ? .red :
            m.pressure == .warn || swapping || full ? .amber : .green

        let usage = "\(Format.memory(m.used)) of \(Format.memory(m.total))"
        let top = groups.sorted { $0.memory > $1.memory }.prefix(3).map {
            "\($0.name) \(Format.memory($0.memory))\($0.processes.count > 1 ? " (\(Format.plural($0.processes.count, "process", "processes")))" : "")"
        }
        let details = top + [
            "Compressed \(Format.memory(m.compressed)) · Cached \(Format.memory(m.cached)) · Swap \(Format.memory(m.swapUsed))",
        ]

        if swapping {
            return Vital(kind: .memory, health: health, value: "Swap \(Format.memory(m.swapUsed))",
                         context: "Your Mac is moving memory to the disk right now, so things feel sluggish.",
                         details: details)
        }
        if health != .green {
            return Vital(kind: .memory, health: health, value: usage,
                         context: "Memory is tight. Quitting heavy apps will help.", details: details)
        }
        if swapGB >= t.notableSwapGB {
            return Vital(kind: .memory, health: .green, value: usage,
                         context: "Plenty of room. \(Format.memory(m.swapUsed)) left on the disk from earlier clears as apps use it, or when you restart.",
                         details: details)
        }
        return Vital(kind: .memory, health: .green, value: usage, context: "Plenty of room.", details: details)
    }

    static func cpu(_ c: CPUReading, groups: [AppGroup], _ t: Thresholds) -> Vital {
        let sustained = c.sustained ?? 0
        let health: Health = sustained > t.cpuRed ? .red : sustained >= t.cpuAmber ? .amber : .green
        let minutes = Int(t.cpuWindow / 60)
        let top = groups.sorted { $0.cpu > $1.cpu }.prefix(3).filter { $0.cpu >= 0.01 }
            .map { "\($0.name) \(Format.percent($0.cpu))" }
        let average = c.sustained.map { "Average over the last \(minutes) min: \(Format.percent($0))" }
            ?? "Collecting a \(minutes)-minute average…"
        return Vital(kind: .cpu, health: health, value: "\(Format.percent(c.current)) busy",
                     context: health == .green ? nil : "Your Mac has been working hard for a while, so it may feel slow and warm.",
                     details: top + [average])
    }

    static func battery(_ b: BatteryReading, _ t: Thresholds) -> Vital {
        let worn = b.serviceRecommended || (b.healthPercent ?? 100) < t.batteryHealthAmber
        let low = b.onBattery && b.charge < t.batteryChargeAmber
        let health: Health =
            b.onBattery && b.charge < t.batteryChargeRed ? .red :
            worn || low ? .amber : .green

        var context: [String] = []
        if low { context.append("Plug in soon.") }
        if worn {
            let wear = [b.healthPercent.map { "\($0)% health" }, b.cycles.map { Format.plural($0, "cycle") }]
                .compactMap { $0 }.joined(separator: ", ")
            context.append("\(wear). Can slow your Mac near empty.")
        }
        if context.isEmpty { context.append(status(b)) }

        var details = [status(b)]
        if let health = b.healthPercent { details.append("Maximum capacity \(health)%") }
        if let cycles = b.cycles { details.append("\(Format.plural(cycles, "charge cycle"))") }
        if b.serviceRecommended { details.append("macOS says service is recommended") }

        return Vital(kind: .battery, health: health, value: "\(b.charge)%",
                     context: context.joined(separator: " "), details: details)
    }

    static func disk(_ d: DiskReading, _ t: Thresholds) -> Vital {
        let freeFraction = Double(d.free) / Double(d.total)
        let health: Health = freeFraction < t.diskFreeRed ? .red : freeFraction <= t.diskFreeAmber ? .amber : .green
        let context: String? = switch health {
        case .green: nil
        case .amber: "Getting full. Clearing caches and old projects frees space."
        case .red: "Almost full. Your Mac slows down and updates can fail."
        }
        let free = Format.disk(d.free)
        let total = Format.disk(d.total)
        return Vital(kind: .disk, health: health, value: "\(free) free", context: context,
                     details: ["\(Format.percent(freeFraction)) of \(total) free"])
    }

    static func uptime(_ seconds: TimeInterval, _ t: Thresholds) -> Vital {
        let days = seconds / 86_400
        let health: Health = days > t.uptimeRedDays ? .red : days >= t.uptimeAmberDays ? .amber : .green
        let value = days >= 1 ? Format.plural(Int(days), "day") : Format.plural(Int(seconds / 3600), "hour")
        return Vital(kind: .uptime, health: health, value: value,
                     context: health == .green ? nil : "A restart clears built-up slowdowns.",
                     details: ["Last restarted \(Date(timeIntervalSinceNow: -seconds).formatted(date: .abbreviated, time: .shortened))"])
    }

    static func temperature(_ state: ProcessInfo.ThermalState) -> Vital {
        switch state {
        case .serious:
            Vital(kind: .temperature, health: .amber, value: "Hot",
                  context: "Your Mac is slowing itself down to cool off.")
        case .critical:
            Vital(kind: .temperature, health: .red, value: "Very hot",
                  context: "Your Mac is heavily throttled. Quit busy apps and give it air.")
        default:
            Vital(kind: .temperature, health: .green, value: "Normal")
        }
    }

    private static func status(_ b: BatteryReading) -> String {
        if b.isCharging { return "Charging" }
        if !b.onBattery { return "Plugged in" }
        guard let minutes = b.minutesRemaining else { return "On battery" }
        return "About \(minutes / 60) h \(minutes % 60) min left"
    }
}
