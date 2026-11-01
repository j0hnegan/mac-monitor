import AppKit

/// Carries out the system-level fix actions. Panel-level ones (acknowledge, show details…)
/// are handled by `MonitorEngine.run`, which calls this for everything else.
@MainActor
enum FixActions {
    static func perform(_ action: FixAction) async {
        switch action {
        case .quitApp(let app):
            quit(app)
        case .restartApp(let app):
            guard let bundleURL = app.bundleURL else { return }
            let running = runningApps(at: bundleURL)
            running.forEach { $0.terminate() }
            // Give the app up to 10 s to quit cleanly before relaunching.
            for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(200))
            }
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: .init(), completionHandler: nil)
        case .forceQuit(let pid):
            kill(pid, SIGKILL)
        case .restartMac:
            var error: NSDictionary?
            NSAppleScript(source: #"tell application "System Events" to restart"#)?.executeAndReturnError(&error)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .showDetails, .acknowledge, .remindTonight:
            break
        }
    }

    private static func quit(_ app: AppGroup) {
        if let bundleURL = app.bundleURL {
            let running = runningApps(at: bundleURL)
            if !running.isEmpty {
                running.forEach { $0.terminate() }
                return
            }
        }
        // Not a regular app (a CLI tool or background agent): ask each process to exit.
        app.processes.forEach { kill($0.pid, SIGTERM) }
    }

    private static func runningApps(at bundleURL: URL) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL == bundleURL.standardizedFileURL }
    }
}
