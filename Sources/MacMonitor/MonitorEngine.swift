import Foundation
import Observation

@Observable
@MainActor
final class MonitorEngine {
    private(set) var vitals: [Vital] = []
    private(set) var alerts: [Alert] = []
    /// The vital row expanded in the panel. Alerts can open one (e.g. "Show Biggest Users").
    var expandedVital: Vital.Kind?

    var visibleVitals: [Vital] { vitals.filter { !preferences.hiddenVitals.contains($0.kind) } }

    var visibleAlerts: [Alert] {
        alerts.filter { !preferences.disabledAlerts.contains($0.kind) && !isSnoozed($0) }
    }

    /// The menu bar dot only reflects what the user has chosen to see.
    var worstHealth: Health {
        (visibleVitals.map(\.health) + visibleAlerts.map(\.severity)).max() ?? .green
    }

    /// Sample faster while the user is looking at the panel.
    var isPanelOpen = false {
        didSet {
            guard isPanelOpen != oldValue else { return }
            // Fresh numbers the moment the panel opens, rather than up to 30 s old.
            if isPanelOpen { sample() }
            startSampling()
        }
    }

    var thresholds = Thresholds()

    /// Called once for each new alert worth interrupting for, when pop-ups are on.
    @ObservationIgnored var onNewAlert: ((Alert) -> Void)?
    @ObservationIgnored private var announced: Set<String> = []

    var preferences = Preferences.load() {
        didSet { preferences.save() }
    }

    @ObservationIgnored private let memory = MemoryCollector()
    @ObservationIgnored private let cpu = CPUCollector()
    @ObservationIgnored private let battery = BatteryCollector()
    @ObservationIgnored private let disk = DiskCollector()
    @ObservationIgnored private let processes = ProcessCollector()
    @ObservationIgnored private let evaluator = AlertEvaluator()
    @ObservationIgnored private var samplingTask: Task<Void, Never>?

    init() {
        startSampling()
        // A short first wait gives the CPU collectors a meaningful first delta.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            self?.sample()
        }
    }

    func sample() {
        let memory = memory.read(window: thresholds.swapWindow)
        let processes = processes.read()
        let groups = ProcessCollector.group(processes)
        let battery = battery.read()
        let disk = disk.read()
        let uptime = UptimeCollector.read()
        let thermal = ProcessInfo.processInfo.thermalState

        let cpu = cpu.read(window: thresholds.cpuWindow)

        var vitals = [
            VitalRules.memory(memory, groups: groups, thresholds),
            VitalRules.cpu(cpu, groups: groups, thresholds),
        ]
        if let battery { vitals.append(VitalRules.battery(battery, thresholds)) }
        if let disk { vitals.append(VitalRules.disk(disk, thresholds)) }
        vitals.append(VitalRules.uptime(uptime, thresholds))
        vitals.append(VitalRules.temperature(thermal, cpu: cpu, groups: groups, thresholds))
        self.vitals = vitals

        let snapshot = SystemSnapshot(memory: memory, processes: processes, groups: groups, battery: battery,
                                      disk: disk, uptime: uptime, thermal: thermal, vitals: vitals)
        alerts = evaluator.evaluate(snapshot, thresholds, ignoredApps: preferences.ignoredApps)
        announceNewAlerts()
        StateFile(snapshot, cpu: cpu, alerts: alerts, overall: worstHealth, engine: self).write()
    }

    /// Forgets alerts that went away, so the same problem coming back pops up again.
    private func announceNewAlerts() {
        let fresh = visibleAlerts.filter { $0.notify && !announced.contains($0.id) }
        announced = announced.union(fresh.map(\.id)).intersection(alerts.map(\.id))
        guard preferences.popUpAlerts else { return }
        fresh.forEach { onNewAlert?($0) }
    }

    // MARK: - Alert actions

    func run(_ fix: Fix, on alert: Alert) async {
        switch fix.action {
        case .acknowledge:
            acknowledge(alert)
        case .remindTonight:
            snooze(alert, until: Self.nextEvening())
        case .showDetails(let kind):
            expandedVital = kind
        default:
            await FixActions.perform(fix.action)
            // Let the process actually exit before re-reading.
            try? await Task.sleep(for: .seconds(1))
            sample()
        }
    }

    func isSnoozed(_ alert: Alert) -> Bool {
        (preferences.snoozedUntil[alert.id] ?? .distantPast) > Date()
    }

    func isAcknowledged(_ alert: Alert) -> Bool {
        preferences.snoozedUntil[alert.id] == .distantFuture
    }

    func snooze(_ alert: Alert, until date: Date) {
        preferences.snoozedUntil[alert.id] = date
    }

    func acknowledge(_ alert: Alert) {
        snooze(alert, until: .distantFuture)
    }

    func ignoreApp(_ name: String) {
        preferences.ignoredApps.insert(name)
        sample()
    }

    func unignoreApp(_ name: String) {
        preferences.ignoredApps.remove(name)
        sample()
    }

    private static func nextEvening() -> Date {
        Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 20), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(6 * 3600)
    }

    private func startSampling() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled, let self {
                try? await Task.sleep(for: .seconds(isPanelOpen ? 4 : 30))
                guard !Task.isCancelled else { return }
                sample()
            }
        }
    }
}
