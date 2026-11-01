import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = MonitorEngine()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var panel = PanelController(engine: engine) { [weak self] in self?.showSettings() }
    private var settingsWindow: NSWindow?
    private var shownHealth: Health?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.registerOnFirstLaunch()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        updateIcon()
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(below: button)
    }

    /// Re-renders the menu bar icon whenever the worst health changes.
    private func updateIcon() {
        withObservationTracking {
            // Every sample replaces vitals and alerts, so this fires often; only redraw on a real change.
            let health = engine.worstHealth
            if health != shownHealth {
                statusItem.button?.image = MenuBarIcon.image(for: health)
                shownHealth = health
            }
        } onChange: {
            Task { @MainActor [weak self] in self?.updateIcon() }
        }
    }

    private func showSettings() {
        panel.close()
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(engine: engine)))
            window.title = "Mac Monitor Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
