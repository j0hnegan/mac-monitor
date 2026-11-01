import Foundation

/// Everything Mac Monitor knows after a sample, written to disk for the read-only `macmon-mcp` server.
/// Files rather than a socket: nothing listens, and the app pays a few small writes per sample.
/// One file per MCP tool, which macmon-mcp serves as-is; the file names are the contract between them.
struct StateFile {
    struct VitalEntry: Encodable {
        let kind: String
        let health: String
        let value: String
        let context: String?
        let details: [String]
        let shownInPanel: Bool
    }

    struct AlertEntry: Encodable {
        let id: String
        let kind: String
        let severity: String
        let title: String
        let detail: String
        /// The buttons Mac Monitor offers for this alert. Informational: the MCP can't press them.
        let offeredFixes: [String]
        let status: String
    }

    struct System: Encodable {
        struct Memory: Encodable {
            let totalGB, usedGB, compressedGB, cachedGB, swapUsedGB: Double
            let pressure: String
        }
        struct CPU: Encodable {
            let busyPercent: Int
            let fiveMinuteAveragePercent: Int?
        }
        struct Disk: Encodable {
            let freeGB, totalGB: Double
        }
        struct Battery: Encodable {
            let chargePercent: Int
            let charging, onBattery: Bool
            let minutesRemaining, cycles, healthPercent: Int?
            let serviceRecommended: Bool
        }

        let memory: Memory
        let cpu: CPU
        let disk: Disk?
        let battery: Battery?
        let uptimeHours: Double
        let thermalState: String
    }

    struct AppEntry: Encodable {
        struct ProcessEntry: Encodable {
            let pid: Int32
            let name: String
            let memoryMB: Int
            let cpuPercent: Int
        }

        let name: String
        let memoryGB: Double
        /// Of one core, like Activity Monitor: 200 means two cores fully busy.
        let cpuPercent: Int
        let processCount: Int
        let bundlePath: String?
        /// The heaviest few, by memory.
        let processes: [ProcessEntry]
    }

    struct Processes: Encodable {
        let note = "Only processes owned by you; system (root) processes aren't readable without admin rights."
        let byMemory: [AppEntry]
        let byCPU: [AppEntry]
    }

    let sampledAt: Date
    let overall: String
    let vitals: [VitalEntry]
    let system: System
    let alerts: [AlertEntry]
    let processes: Processes

    private struct VitalsFile: Encodable {
        let sampledAt: Date
        let overall: String
        let vitals: [VitalEntry]
        let system: System
    }

    private struct AlertsFile: Encodable {
        let sampledAt: Date
        let alerts: [AlertEntry]
    }

    private struct ProcessesFile: Encodable {
        let sampledAt: Date
        let processes: Processes
    }

    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "MacMonitor/state")

    func write() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        Self.write(VitalsFile(sampledAt: sampledAt, overall: overall, vitals: vitals, system: system), to: "vitals.json")
        Self.write(AlertsFile(sampledAt: sampledAt, alerts: alerts), to: "alerts.json")
        Self.write(ProcessesFile(sampledAt: sampledAt, processes: processes), to: "processes.json")
    }

    private static func write(_ value: some Encodable, to name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        let url = directory.appending(path: name)
        try? data.write(to: url, options: [.atomic])
        // Process names and paths are nobody else's business on a shared Mac.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

@MainActor
extension StateFile {
    init(_ s: SystemSnapshot, cpu: CPUReading, alerts: [Alert], overall: Health, engine: MonitorEngine) {
        let preferences = engine.preferences
        sampledAt = Date()
        self.overall = "\(overall)"
        vitals = s.vitals.map { vital in
            VitalEntry(kind: vital.kind.rawValue, health: "\(vital.health)", value: vital.value, context: vital.context,
                       details: vital.details, shownInPanel: !preferences.hiddenVitals.contains(vital.kind))
        }
        self.alerts = alerts.map { alert in
            let status = if preferences.disabledAlerts.contains(alert.kind) {
                "hidden: this alert type is turned off in Settings"
            } else if engine.isAcknowledged(alert) {
                "acknowledged: the user said they know about it"
            } else if engine.isSnoozed(alert), let until = preferences.snoozedUntil[alert.id] {
                "snoozed until \(until.formatted(.iso8601))"
            } else {
                "active"
            }
            return AlertEntry(id: alert.id, kind: alert.kind.rawValue, severity: "\(alert.severity)", title: alert.title,
                              detail: alert.detail, offeredFixes: alert.fixes.map(\.title), status: status)
        }
        system = System(
            memory: .init(totalGB: Self.gb(s.memory.total), usedGB: Self.gb(s.memory.used),
                          compressedGB: Self.gb(s.memory.compressed), cachedGB: Self.gb(s.memory.cached),
                          swapUsedGB: Self.gb(s.memory.swapUsed), pressure: "\(s.memory.pressure)"),
            cpu: .init(busyPercent: Self.percent(cpu.current), fiveMinuteAveragePercent: cpu.sustained.map(Self.percent)),
            // Decimal units for disk, matching Finder and the app's Disk vital.
            disk: s.disk.map { .init(freeGB: Self.rounded(Double($0.free) / 1e9), totalGB: Self.rounded(Double($0.total) / 1e9)) },
            battery: s.battery.map {
                .init(chargePercent: $0.charge, charging: $0.isCharging, onBattery: $0.onBattery,
                      minutesRemaining: $0.minutesRemaining, cycles: $0.cycles, healthPercent: $0.healthPercent,
                      serviceRecommended: $0.serviceRecommended)
            },
            uptimeHours: Self.rounded(s.uptime / 3600),
            thermalState: Self.name(s.thermal)
        )
        processes = Processes(
            byMemory: s.groups.sorted { $0.memory > $1.memory }.prefix(10).map(Self.entry),
            byCPU: s.groups.sorted { $0.cpu > $1.cpu }.prefix(10).map(Self.entry)
        )
    }

    private static func entry(_ app: AppGroup) -> AppEntry {
        AppEntry(
            name: app.name, memoryGB: gb(app.memory), cpuPercent: percent(app.cpu), processCount: app.processes.count,
            bundlePath: app.bundleURL?.path,
            processes: app.processes.sorted { $0.memory > $1.memory }.prefix(5).map {
                .init(pid: $0.pid, name: $0.name, memoryMB: Int($0.memory / 1_048_576), cpuPercent: percent($0.cpu))
            }
        )
    }

    /// Memory in binary units, matching Activity Monitor and the app's Memory vital.
    private static func gb(_ bytes: UInt64) -> Double { rounded(Format.gigabytes(bytes)) }

    private static func rounded(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    private static func percent(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }

    private static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
