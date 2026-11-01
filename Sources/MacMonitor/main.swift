import AppKit

// A plain AppKit entry point: the menu bar panel is a custom NSPanel (see PanelController),
// which gives control over its shape, background, and resizing that MenuBarExtra doesn't.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}
