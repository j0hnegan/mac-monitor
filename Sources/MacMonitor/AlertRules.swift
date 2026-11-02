import Foundation

struct SystemSnapshot {
    let memory: MemoryReading
    let processes: [ProcessSample]
    let groups: [AppGroup]
    let battery: BatteryReading?
    let disk: DiskReading?
    let uptime: TimeInterval
    let thermal: ProcessInfo.ThermalState
    let vitals: [Vital]

    func health(_ kind: Vital.Kind) -> Health {
        vitals.first { $0.kind == kind }?.health ?? .green
    }
}

/// Turns snapshots into alerts (PRD §7). Keeps the state needed for "sustained for N minutes" rules.
final class AlertEvaluator {
    private var busySince: [pid_t: Date] = [:]
    private var memoryRedSince: Date?

    func evaluate(_ s: SystemSnapshot, _ t: Thresholds, ignoredApps: Set<String>) -> [Alert] {
        let ownPID = getpid()
        let groups = s.groups.filter { group in
            !ignoredApps.contains(group.name) && !group.processes.contains { $0.pid == ownPID }
        }

        var alerts = memoryHogs(s, groups, t) + runaways(s, groups, t)
        alerts += [memoryPressure(s, groups, t), uptime(s, t), lowBatteryDegraded(s, t),
                   batteryService(s, t), lowDisk(s), thermal(s, groups)].compactMap { $0 }
        return alerts.sorted { $0.severity > $1.severity }
    }

    /// Only when memory is actually tight: a big app on a Mac with plenty of room isn't a problem.
    private func memoryHogs(_ s: SystemSnapshot, _ groups: [AppGroup], _ t: Thresholds) -> [Alert] {
        let memoryHealth = s.health(.memory)
        guard memoryHealth != .green else { return [] }
        let sorted = groups.sorted { $0.memory > $1.memory }

        return sorted
            .filter { Format.gigabytes($0.memory) > t.memoryHogGB || $0.id == sorted.first?.id }
            .map { app in
                let share = Double(app.memory) / Double(s.memory.total)
                let remedy = app.bundleURL == nil
                    ? "Quitting it frees memory."
                    : "Restarting it frees memory; most apps reopen where you left off."
                return Alert(
                    kind: .memoryHog,
                    subject: "\(app.name):\(app.processes.map(\.pid).min() ?? 0)",
                    severity: memoryHealth == .red ? .red : .amber,
                    title: "\(app.name) is using \(Format.share(share)) your memory",
                    detail: "Your Mac is short on memory, which slows everything down. \(remedy)",
                    fixes: appFixes(app),
                    // One pop-up for the biggest app; the rest wait in the panel.
                    notify: memoryHealth == .red && app.id == sorted.first?.id,
                    app: app.name
                )
            }
    }

    private func runaways(_ s: SystemSnapshot, _ groups: [AppGroup], _ t: Thresholds) -> [Alert] {
        let now = Date()
        // macOS's own background work (photo analysis, Spotlight indexing, backups) runs hard for a
        // while and finishes on its own; it isn't stuck, and force quitting it just restarts it.
        let busy = s.processes.filter { $0.cpu > t.runawayCPU && !$0.path.hasPrefix("/System/") && !$0.path.hasPrefix("/usr/") }
        busySince = busy.reduce(into: [:]) { $0[$1.pid] = busySince[$1.pid] ?? now }

        return busy.compactMap { process in
            let duration = now.timeIntervalSince(busySince[process.pid] ?? now)
            guard duration >= t.runawayWindow,
                  let app = groups.first(where: { $0.processes.contains { $0.pid == process.pid } })
            else { return nil }

            var fixes = app.bundleURL == nil ? [] : [Fix(id: "restart_app", title: "Restart \(app.name)", action: .restartApp(app))]
            fixes.append(Fix(id: "force_quit", title: "Force Quit", action: .forceQuit(pid: process.pid)))
            return Alert(
                kind: .runawayProcess,
                subject: String(process.pid),
                severity: .amber,
                title: "\(app.name) is stuck using a lot of CPU",
                detail: "It's been working your processor hard for \(Int(duration / 60)) min, draining your battery and heating your Mac. That usually means it's stuck in a loop; \(app.bundleURL == nil ? "force quitting" : "a restart") fixes it.",
                fixes: fixes,
                notify: true,
                app: app.name,
                autoFixable: app.bundleURL != nil
            )
        }
    }

    private func memoryPressure(_ s: SystemSnapshot, _ groups: [AppGroup], _ t: Thresholds) -> Alert? {
        memoryRedSince = s.health(.memory) == .red ? (memoryRedSince ?? Date()) : nil
        guard let since = memoryRedSince, Date().timeIntervalSince(since) >= t.memoryPressureWindow else { return nil }

        let top = groups.sorted { $0.memory > $1.memory }.prefix(3)
            .map { "\($0.name) \(Format.memory($0.memory))" }.joined(separator: ", ")
        return Alert(kind: .memoryPressure, subject: "system", severity: .red,
                     title: "Your Mac is out of memory",
                     detail: "Everything slows down until something quits. Biggest users: \(top).",
                     fixes: [Fix(id: "show_details", title: "Show Biggest Users", action: .showDetails(.memory))],
                     notify: true)
    }

    private func uptime(_ s: SystemSnapshot, _ t: Thresholds) -> Alert? {
        let days = Int(s.uptime / 86_400)
        guard Double(days) > t.uptimeAlertDays else { return nil }
        // Keyed to this boot, so acknowledging it doesn't silence the next one.
        let bootTime = Int(Date().timeIntervalSince1970 - s.uptime) / 60
        return Alert(
            kind: .uptime, subject: String(bootTime), severity: max(s.health(.uptime), .amber),
            title: "Your Mac hasn't restarted in \(days) days",
            detail: "A restart clears built-up slowdowns. Save your work first; open apps will close.",
            fixes: [
                Fix(id: "restart_mac", title: "Restart Mac", action: .restartMac,
                    confirmation: "Save your work first. Mac Monitor can't save anything for you, and open apps will be asked to quit."),
                Fix(id: "remind_tonight", title: "Remind Me Tonight", action: .remindTonight),
            ],
            notify: true
        )
    }

    private func lowBatteryDegraded(_ s: SystemSnapshot, _ t: Thresholds) -> Alert? {
        guard let b = s.battery, b.onBattery, b.charge < t.lowBatteryCharge, b.serviceRecommended else { return nil }
        return Alert(kind: .lowBatteryDegraded, subject: "battery", severity: .red,
                     title: "Plug in soon",
                     detail: "Your battery is worn, so your Mac slows down as it gets close to empty.",
                     notify: true)
    }

    private func batteryService(_ s: SystemSnapshot, _ t: Thresholds) -> Alert? {
        guard let b = s.battery, b.serviceRecommended || (b.healthPercent ?? 100) < t.batteryServiceHealth else { return nil }
        let wear = [b.healthPercent.map { "\($0)% of its original capacity" }, b.cycles.map { "after \(Format.plural($0, "cycle"))" }]
            .compactMap { $0 }.joined(separator: " ")
        return Alert(
            kind: .batteryService, subject: "battery", severity: .amber,
            title: "Your battery needs service",
            detail: "It holds \(wear). It drains faster and can slow your Mac when low.",
            fixes: [
                Fix(id: "acknowledge", title: "Got It", action: .acknowledge),
                Fix(id: "open_battery_support", title: "Apple Battery Service",
                    action: .openURL(URL(string: "https://support.apple.com/mac/repair")!)),
            ],
            notify: true
        )
    }

    private func lowDisk(_ s: SystemSnapshot) -> Alert? {
        guard s.health(.disk) == .red, let disk = s.disk else { return nil }
        return Alert(
            kind: .lowDisk, subject: "disk", severity: .red,
            title: "Your disk is almost full",
            detail: "Only \(Format.disk(disk.free)) left. Your Mac slows down and updates can fail.",
            fixes: [Fix(id: "open_storage_settings", title: "Open Storage Settings",
                        action: .openURL(URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!))],
            notify: true
        )
    }

    private func thermal(_ s: SystemSnapshot, _ groups: [AppGroup]) -> Alert? {
        guard s.thermal == .serious || s.thermal == .critical else { return nil }
        let busiest = groups.max { $0.cpu < $1.cpu }.map { " \($0.name) is the busiest app." } ?? ""
        return Alert(
            kind: .thermal, subject: "system", severity: s.thermal == .critical ? .red : .amber,
            title: "Your Mac is running hot",
            detail: "It's slowing itself down to cool off.\(busiest)",
            fixes: [Fix(id: "show_details", title: "Show Busiest Apps", action: .showDetails(.cpu))],
            notify: true
        )
    }

    private func appFixes(_ app: AppGroup) -> [Fix] {
        let quit = Fix(id: "quit_app", title: "Quit \(app.name)", action: .quitApp(app))
        guard app.bundleURL != nil else { return [quit] }
        return [Fix(id: "restart_app", title: "Restart \(app.name)", action: .restartApp(app)), quit]
    }
}
