import AppKit
import Observation
import SwiftUI

/// A pop-up in the top-right corner, with a sound, for alerts worth interrupting for. It stays until
/// dismissed or the problem goes away, so it isn't missed while you're away. A stuck app you aren't
/// using restarts itself after a short countdown unless you stop it.
@MainActor
final class AlertToastController {
    private let engine: MonitorEngine
    private let openPanel: () -> Void
    private let model = ToastModel()
    private let panel: KeyablePanel
    private let hosting: NSHostingView<AlertToastView>
    private var queue: [Alert] = []
    private var countdown: Task<Void, Never>?

    private static let width: CGFloat = 360
    private static let cornerRadius: CGFloat = 16
    private static let margin: CGFloat = 10
    private static let countdownSeconds = 10.0

    init(engine: MonitorEngine, openPanel: @escaping () -> Void) {
        self.engine = engine
        self.openPanel = openPanel
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hosting = NSHostingView(rootView: AlertToastView(model: model, onFix: { _ in }, onStop: {}, onClose: {}))
        hosting.rootView = AlertToastView(
            model: model,
            onFix: { [weak self] in self?.run($0) },
            onStop: { [weak self] in self?.stopCountdown() },
            onClose: { [weak self] in self?.close() }
        )

        // Measure the content, but let only present() and fit() size the window, as the panel does.
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // Clicking a button shouldn't take the keyboard away from what you're typing in.
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = PanelController.glassBackground(around: hosting, cornerRadius: Self.cornerRadius)
    }

    func show(_ alert: Alert) {
        guard model.alert == nil else {
            if model.alert?.id != alert.id, !queue.contains(where: { $0.id == alert.id }) { queue.append(alert) }
            return
        }
        model.alert = alert
        model.done = nil
        if let (fix, app) = autoFix(for: alert) {
            model.autoFix = AutoFix(fix: fix, appName: app, seconds: Self.countdownSeconds)
            countdown = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.countdownSeconds))
                guard let self, !Task.isCancelled else { return }
                // You may have switched to the app during the countdown.
                autoFix(for: alert) == nil ? stopCountdown() : run(fix)
            }
        }
        NSSound(named: "Glass")?.play()
        // SwiftUI draws the new alert on its next pass; measured now, the view is still empty.
        DispatchQueue.main.async { [weak self] in self?.present() }
        closeWhenResolved()
    }

    /// Only a stuck app with a restart fix, and only while you're not using it.
    private func autoFix(for alert: Alert) -> (Fix, String)? {
        guard engine.preferences.autoFixStuckApps, alert.autoFixable,
              let fix = alert.fixes.first, case .restartApp(let app) = fix.action,
              let bundleURL = app.bundleURL,
              NSWorkspace.shared.frontmostApplication?.bundleURL?.standardizedFileURL != bundleURL.standardizedFileURL
        else { return nil }
        return (fix, app.name)
    }

    private func run(_ fix: Fix) {
        stopCountdown()
        guard let alert = model.alert else { return }
        if let message = fix.confirmation, !confirm(fix.title, message) { return }

        let name = alert.app ?? "the app"
        let result: (working: String, done: String)? = switch fix.action {
        case .restartApp: ("Restarting \(name)…", "Restarted \(name)")
        case .quitApp: ("Quitting \(name)…", "Quit \(name)")
        case .forceQuit: ("Force quitting \(name)…", "Force quit \(name)")
        default: nil
        }
        // Hides the buttons while it works, so the fix can't be started twice.
        model.done = result?.working
        fit()

        Task {
            await engine.run(fix, on: alert)
            guard model.alert?.id == alert.id else { return }
            guard let result else {
                close()
                if case .showDetails = fix.action { openPanel() }
                return
            }
            // A hung app can ignore the request to quit; don't claim success then.
            let fixed = !engine.alerts.contains { $0.id == alert.id }
            model.done = fixed ? result.done : "\(name) didn't quit. Try Force Quit in the panel."
            fit()
            // A short confirmation, so a fix that ran on its own doesn't go unnoticed.
            try? await Task.sleep(for: .seconds(fixed ? 3 : 6))
            if model.alert?.id == alert.id { close() }
        }
    }

    private func stopCountdown() {
        countdown?.cancel()
        countdown = nil
        model.autoFix = nil
        fit()
    }

    private func confirm(_ title: String, _ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: title)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Closes the pop-up if the alert clears on its own (or from the panel) while it's showing.
    private func closeWhenResolved() {
        withObservationTracking {
            _ = engine.alerts
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, let alert = model.alert else { return }
                if model.done == nil, !engine.visibleAlerts.contains(where: { $0.id == alert.id }) {
                    close()
                } else {
                    closeWhenResolved()
                }
            }
        }
    }

    private func present() {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let height = hosting.fittingSize.height
        let frame = NSRect(x: visible.maxX - Self.width - Self.margin, y: visible.maxY - Self.margin - height,
                           width: Self.width, height: height)

        panel.setFrame(frame.offsetBy(dx: 20, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.invalidateShadow() }
        }
    }

    /// Resizes to the content after it changes, keeping the top edge in place.
    private func fit() {
        DispatchQueue.main.async { [self] in
            let height = hosting.fittingSize.height
            guard panel.isVisible, abs(panel.frame.height - height) > 0.5 else { return }
            var frame = panel.frame
            frame.origin.y = frame.maxY - height
            frame.size.height = height
            panel.setFrame(frame, display: true, animate: true)
            panel.invalidateShadow()
        }
    }

    private func close() {
        guard model.alert != nil else { return }
        stopCountdown()
        model.alert = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(panel.frame.offsetBy(dx: 20, dy: 0), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new alert may have taken over the pop-up during the animation.
                guard let self, self.model.alert == nil else { return }
                self.panel.orderOut(nil)
                self.showNext()
            }
        }
    }

    /// Skips queued alerts that have cleared up in the meantime.
    private func showNext() {
        let current = Set(engine.visibleAlerts.map(\.id))
        queue.removeAll { !current.contains($0.id) }
        guard !queue.isEmpty else { return }
        show(queue.removeFirst())
    }
}

@Observable
@MainActor
final class ToastModel {
    var alert: Alert?
    var autoFix: AutoFix?
    /// Set after a fix runs; the pop-up shows it briefly, then closes.
    var done: String?
}

struct AutoFix {
    let fix: Fix
    let appName: String
    let seconds: TimeInterval
    let deadline: Date

    init(fix: Fix, appName: String, seconds: TimeInterval) {
        self.fix = fix
        self.appName = appName
        self.seconds = seconds
        deadline = Date().addingTimeInterval(seconds)
    }
}

@MainActor
struct AlertToastView: View {
    let model: ToastModel
    let onFix: (Fix) -> Void
    let onStop: () -> Void
    let onClose: () -> Void
    @State private var copied = false

    var body: some View {
        if let alert = model.alert {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.done == nil ? alert.kind.symbol : "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(model.done == nil ? alert.severity.color : Health.green.color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.done ?? alert.title)
                            .fontWeight(.medium)
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Close")
                    }
                    if model.done == nil {
                        Text(alert.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let autoFix = model.autoFix {
                            CountdownBar(autoFix: autoFix)
                                .padding(.top, 6)
                        }
                        buttons(for: alert)
                            .padding(.top, 6)
                    }
                }
            }
            .padding(12)
            .frame(width: 360)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            .focusEffectDisabled()
            .onChange(of: alert.id) { copied = false }
        }
    }

    private func buttons(for alert: Alert) -> some View {
        HStack(spacing: 6) {
            if let autoFix = model.autoFix {
                IconButton(title: "Restart Now", help: autoFix.fix.title) { onFix(autoFix.fix) }
                IconButton(title: "Don't Restart", help: "Stop the countdown", action: onStop)
            } else if let primary = alert.fixes.first {
                IconButton(title: primary.title, help: primary.title) { onFix(primary) }
            }
            Spacer()
            IconButton(title: copied ? "Copied" : "Copy for Claude",
                       help: "Copy this alert and Mac Monitor's data to paste into Claude") {
                ClaudePrompt.copy(for: alert)
                copied = true
            }
        }
    }
}

private struct CountdownBar: View {
    let autoFix: AutoFix
    private static let height: CGFloat = 4

    var body: some View {
        TimelineView(.animation) { context in
            let left = max(0, autoFix.deadline.timeIntervalSince(context.date))
            VStack(alignment: .leading, spacing: 4) {
                Text("Restarting \(autoFix.appName) in \(Int(left.rounded(.up)))s")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.7))
                                .frame(width: geometry.size.width * (1 - left / autoFix.seconds))
                        }
                }
                .frame(height: Self.height)
            }
        }
    }
}
